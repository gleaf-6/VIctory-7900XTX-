//! A buffer's size the program reads from its descriptor (a record count
//! taken as a number, `descriptor_data`) is asked through a heap handle of
//! its own, marked non-uniform: AMD's compiler (`amdxc64.dll`, RX 9070 XT,
//! driver 32.0.32029.2010) reads a null pointer compiling the query through
//! the uniform handle the buffer's loads use, and the process ends. The
//! program is the one of fork pull request #452 (MalfoyDraco99).

use super::host::Host;
use super::{HostShader, lower, validator};
use crate::native::{
    ComputeIo, HwStage, NativeProgram, ResourceType, RootParam, RootType, StageIo, UsedResource,
};
use crate::{io, ir, resource, structure};

/// A buffer descriptor loaded in a branch whose record count (dword 2) the
/// program takes as a number, the offset it loads at; the UAV of the
/// result loaded before the branch.
const WORDS: [u32; 19] = [
    0xBE84_0300, // s_mov_b32 s4, s0
    0xBE85_0380, // s_mov_b32 s5, 0
    0xF408_0402,
    0xFA00_0020, // s_load_dwordx4 s[16:19], s[4:5], 0x20 (the result's UAV)
    0xBF8C_C07F, // s_waitcnt lgkmcnt(0)
    0x7D88_0081, // v_cmp_gt_u32 vcc_lo, 1, v0 (lane 0)
    0xBE94_3C6A, // s_and_saveexec_b32 s20, vcc_lo
    0xBF88_0008, // s_cbranch_execz to the end of the branch
    0xF408_0202,
    0xFA00_0000, // s_load_dwordx4 s[8:11], s[4:5], 0 (the buffer)
    0xBF8C_C07F, // s_waitcnt lgkmcnt(0)
    0x7E00_020A, // v_mov_b32 v0, s10: the record count as a number
    0xE030_1000,
    0x8002_0100, // buffer_load_dword v1, v0, s[8:11], 0 offen
    0xBF8C_3F70, // s_waitcnt vmcnt(0)
    0x887E_147E, // s_or_b32 exec_lo, exec_lo, s20
    0xE070_1000,
    0x8004_0100, // buffer_store_dword v1, v0, s[16:19], 0 offen
    0xBF81_0000, // s_endpgm
];

/// [`WORDS`] lowered as a wave32 compute program with a table of an SRV and
/// a UAV at s0.
fn lowered() -> lower::Lowered {
    let native = NativeProgram {
        stage: HwStage::Cs,
        wave64: false,
        vgprs: 8,
        layout: vec![RootParam {
            root: RootType::Table,
            table_offset_dwords: 0,
            sgprs: 1,
            base_register: 0,
            user_data: 0,
            slot: 0,
        }],
        used: [(ResourceType::Srv, 0), (ResourceType::Uav, 8)]
            .into_iter()
            .map(|(kind, table_offset_dwords)| UsedResource {
                kind,
                root: RootType::Table,
                table_offset_dwords,
                lower_bound: 0,
                stride: 0,
                dwords: 4,
                user_data: 0,
                slot: 0,
            })
            .collect(),
        io: StageIo::Cs(ComputeIo {
            rsrc2: 0,
            threads: [32, 1, 1],
        }),
        code: WORDS.iter().flat_map(|w| w.to_le_bytes()).collect(),
    };
    let p = ir::build(&native.code, native.wave64, native.vgprs).expect("ir::build");
    let st = structure::structure(&p).expect("structure");
    let res = resource::track(&p, &native.layout, native.stage, Some(&st)).expect("track");
    let io = io::raise(&p, &native).expect("io::raise");
    lower::lower(&lower::Parts {
        native: &native,
        p: &p,
        st: &st,
        io: &io,
        res: &res,
        inputs: Vec::new(),
        outputs: Vec::new(),
        prims: Vec::new(),
        mesh_stride: 0,
    })
    .expect("lower")
}

/// Without the handle of its own, AMD's compiler ends the test process here.
#[test]
fn a_buffer_size_read_as_a_number_compiles_on_the_host() {
    let l = lowered();
    let shader = HostShader {
        stage: HwStage::Cs,
        dxil: l.dxil,
        user_data: l.user_data,
        samplers: l.samplers,
        static_samplers: Vec::new(),
        root_cbvs: l.root_cbvs,
        root_srvs: l.root_srvs,
        root_uavs: l.root_uavs,
        root_indexed_views: Vec::new(),
    };
    if let Ok(mut v) = validator::Validator::load(validator::Validator::default_path().as_deref()) {
        v.validate(&mut shader.dxil.clone())
            .expect("DXIL validation failed");
    }
    let _one = super::valu_tests::ONE_AT_A_TIME
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    for warp in [false, true] {
        let Ok(host) = Host::new(warp) else {
            continue;
        };
        host.compute_pipeline(&shader)
            .unwrap_or_else(|e| panic!("warp={warp}: compute_pipeline failed: {e}"));
    }
}
