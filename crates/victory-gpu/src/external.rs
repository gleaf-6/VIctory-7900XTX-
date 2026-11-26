//! Host work that a host library records into a title's command list in
//! place of a console one (the host's FidelityFX upscaler, say): the host
//! device, a title texture's host copy in the state the library is told,
//! and the host list itself.

use windows::Win32::Graphics::Direct3D12::{
    ID3D12Device, ID3D12GraphicsCommandList, ID3D12Resource,
};

use windows::core::Interface;

use crate::object::Object;

/// The host D3D12 device, created on first use; `None` without a host GPU.
pub fn host_device() -> Option<ID3D12Device> {
    crate::host::host().map(|h| h.device.clone())
}

/// A title texture's host copy, moved to the host resource `state` in the
/// title list `list`, and the state it is in: `state` without the bits the
/// host copy cannot take (see `host::legal_state`). What the list records
/// next finds it there and must leave it there. The list holds the texture
/// until it is reset. `None` for a buffer, or without a host list.
pub fn host_texture(
    list: *const Object,
    resource: *const Object,
    state: u32,
) -> Option<(ID3D12Resource, u32)> {
    let host = crate::list::host_list(list).or_else(crate::list::current_host_list)?;
    let texture = crate::resource::host_resource(resource)?.clone();
    crate::list::ensure_state(host, resource, state);
    let state = crate::host::legal_state(&texture, state);
    Some((texture, state))
}

/// Runs `f` with the host list behind the title list `list` (open for
/// recording); `None` without one. What `f` binds (descriptor heaps, root
/// signatures, pipeline) is replaced before the list's next draw or
/// dispatch.
pub fn record<R>(
    list: *const Object,
    f: impl FnOnce(&ID3D12GraphicsCommandList) -> R,
) -> Option<R> {
    let mut out = None;
    crate::list::with_state_or_current(list, |host, state| {
        out = Some(f(&host.list));
        state.host_state_lost();
    });
    out
}
/// Which half of [host_texture] is missing, for another module's log:
/// whether the title list has a host list, and whether the title resource has
/// a host copy.
pub fn probe(list: *const Object, resource: *const Object) -> (bool, bool) {
    (
        crate::list::host_list(list).is_some(),
        crate::resource::host_resource(resource).is_some(),
    )
}
/// The host side of a thin list, for a call a host library records for later
/// ([`defer`]): the command list the library records into, and where its
/// textures are looked up. Opaque: the library names only this handle.
pub struct HostSide(*const crate::host::HostList);

impl HostSide {
    /// The command list, as the library's `commandList` field wants it.
    pub fn raw(&self) -> *mut std::ffi::c_void {
        // SAFETY: the handle is made for the call that receives it.
        unsafe { self.0.as_ref() }.map_or(std::ptr::null_mut(), |h| {
            h.list.as_raw()
        })
    }
}

/// Records a host library's call for a thin list (`words` are the library's
/// own): true when it was recorded, false when the list is not thin and the
/// caller runs the call now.
pub fn defer(list: *const Object, words: &[u64]) -> bool {
    crate::list::thin::host_call(list, words)
}

/// The handler that runs a deferred call, registered by the library's module
/// (`use_host_call`).
pub type HostCall = fn(&HostSide, &[u64]) -> bool;

static HOST_CALL: std::sync::OnceLock<HostCall> = std::sync::OnceLock::new();

/// Registers the handler for deferred calls; the first wins.
pub fn use_host_call(handler: HostCall) {
    let _ = HOST_CALL.set(handler);
}

/// Runs a deferred call of a host library, from the list's translation:
/// false if no handler is registered or it refused (the list stops there).
pub(crate) fn host_call(list: &crate::host::HostList, words: &[u64]) -> bool {
    HOST_CALL
        .get()
        .is_some_and(|handler| handler(&HostSide(list as *const _), words))
}

/// A title texture's host copy, moved to `state` on the host side of a thin
/// list's translation (the same as [`host_texture`], for a list whose host
/// side is being written by our threads).
pub fn host_texture_on(
    host: &HostSide,
    resource: *const Object,
    state: u32,
) -> Option<(ID3D12Resource, u32)> {
    // SAFETY: the handle is made for the call that receives it.
    let host = unsafe { host.0.as_ref() }?;
    let texture = crate::resource::host_resource(resource)?.clone();
    crate::list::ensure_state(host, resource, state);
    let state = crate::host::legal_state(&texture, state);
    Some((texture, state))
}
