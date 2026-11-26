//! The picture of a frame: the host textures a frame wrote into since its last
//! present, and whether the presented one is among them.
//!
//! A console's display compositor takes the surface a frame rendered and
//! scales it to the output. This layer has no equivalent: a title that
//! presents a resource nothing in the frame wrote (the Series S menus draw
//! into 3840x2160 targets and present a 1920x1080 resource) shows nothing,
//! however much it drew. When that happens, the largest texture the frame
//! wrote stands in for the presented one and the swap chain scales it
//! ([`crate::queue`]'s present). That is an approximation, not the console's
//! compositor, and it says so in the log once.

use std::sync::Mutex;

/// What the frame wrote into: the host texture, and the title resource behind
/// it (0: a host library's pass, with no title resource of ours to show).
static WROTE: Mutex<Vec<(usize, usize)>> = Mutex::new(Vec::new());

/// How many textures a frame is remembered through (a frame of this title
/// writes a few dozen).
const KEEP: usize = 512;

/// A texture stands in only when it is at least this many times the
/// presented one's area: a target of the same size is not the picture.
const LARGER: u64 = 2;

macro_rules! once {
    ($($arg:tt)*) => {{
        static ONCE: std::sync::Once = std::sync::Once::new();
        ONCE.call_once(|| tracing::info!($($arg)*));
    }};
}

/// Notes that a pass wrote into the title resource `resource`, whose host
/// texture is `texture`.
#[cfg(windows)]
pub(crate) fn wrote(resource: usize, texture: usize) {
    if resource == 0 || texture == 0 {
        return;
    }
    let mut wrote = WROTE.lock().unwrap_or_else(|e| e.into_inner());
    if wrote.iter().any(|&(t, _)| t == texture) {
        return;
    }
    if wrote.len() < KEEP {
        wrote.push((texture, resource));
    }
}

/// Notes that a host library's pass wrote into the host texture `texture`
/// (FidelityFX's upscaling writes the picture it is given).
pub fn wrote_host(texture: usize) {
    if texture == 0 {
        return;
    }
    let mut wrote = WROTE.lock().unwrap_or_else(|e| e.into_inner());
    if wrote.iter().any(|&(t, _)| t == texture) {
        return;
    }
    if wrote.len() < KEEP {
        wrote.push((texture, 0));
    }
}

/// The frame's list is taken (a present that did not need it, having
/// composed its planes): the next present begins a new one.
#[cfg(windows)]
pub(crate) fn forget() {
    WROTE.lock().unwrap_or_else(|e| e.into_inner()).clear();
}

/// At a present of the host texture `presented`, `(width, height)`: `None`
/// when the frame wrote it (what is presented is the picture), else the
/// largest texture the frame wrote that is [`LARGER`] times its area, as its
/// title resource. The frame's list is taken either way: the next present
/// begins a new one.
#[cfg(windows)]
pub(crate) fn stand_in(presented: usize, width: u32, height: u32) -> Option<crate::object::This> {
    let wrote = std::mem::take(&mut *WROTE.lock().unwrap_or_else(|e| e.into_inner()));
    if wrote.iter().any(|&(texture, _)| texture == presented) {
        return None;
    }
    let wanted = u64::from(width) * u64::from(height) * LARGER;
    let mut best: Option<(u64, usize, usize, u32, u32)> = None;
    for &(texture, resource) in &wrote {
        if resource == 0 {
            continue;
        }
        let Some(host) = crate::resource::host_resource(resource as crate::object::This) else {
            continue;
        };
        // SAFETY: a live host resource.
        let desc = unsafe { host.GetDesc() };
        let area = u64::from(desc.Width) * u64::from(desc.Height);
        if area < wanted || area <= best.map_or(0, |b| b.0) {
            continue;
        }
        best = Some((area, texture, resource, desc.Width as u32, desc.Height));
    }
    let (area, texture, resource, w, h) = best?;
    once!(
        presented_w = width,
        presented_h = height,
        stand_in = format_args!("{texture:#x}"),
        resource = format_args!("{resource:#x}"),
        w,
        h,
        area,
        "present: nothing wrote the presented resource in this frame; the largest texture the frame wrote stands in, scaled by the swap chain"
    );
    Some(resource as crate::object::This)
}
