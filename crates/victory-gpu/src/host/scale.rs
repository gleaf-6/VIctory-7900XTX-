//! Scaling a texture into the swap chain's buffer on the card: one fullscreen
//! triangle and a bilinear sampler. Used by a present whose texture is not the
//! swap chain's size (the Series S menus, drawn at 3840x2160 and shown in a
//! 1920x1080 window): making the swap chain's buffers again for another size
//! flickers, so the picture is drawn into the buffers as they are instead.

use windows::Win32::Graphics::Direct3D::D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
use windows::Win32::Graphics::Direct3D12::*;
use windows::Win32::Graphics::Dxgi::Common::*;
use windows::core::Interface;

const SOURCE: &str = r#"
#define RS "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), DescriptorTable(SRV(t0), visibility=SHADER_VISIBILITY_PIXEL), StaticSampler(s0, filter=FILTER_MIN_MAG_MIP_LINEAR, addressU=TEXTURE_ADDRESS_CLAMP, addressV=TEXTURE_ADDRESS_CLAMP, visibility=SHADER_VISIBILITY_PIXEL)"
Texture2D<float4> picture : register(t0);
SamplerState sam : register(s0);
struct VsOut {
    float4 at : SV_Position;
    float2 uv : TEXCOORD0;
};
[RootSignature(RS)]
VsOut vs(uint id : SV_VertexID) {
    VsOut o;
    float2 p = float2((id << 1) & 2, id & 2);
    o.uv = p;
    o.at = float4(p * float2(2, -2) + float2(-1, 1), 0, 1);
    return o;
}
[RootSignature(RS)]
float4 ps(VsOut i) : SV_Target { return picture.Sample(sam, i.uv); }
"#;

/// The scaler: a pipeline state for one swap chain format, the root signature
/// its shaders carry, and the one-view heap they read through.
pub(super) struct Scale {
    pso: ID3D12PipelineState,
    root: ID3D12RootSignature,
    heap: ID3D12DescriptorHeap,
}

impl Scale {
    /// Makes the scaler for a swap chain of `format`.
    pub(super) fn new(device: &ID3D12Device, format: DXGI_FORMAT) -> windows::core::Result<Scale> {
        let vs = super::compile(SOURCE, windows::core::s!("vs"), windows::core::s!("vs_5_1"))?;
        let ps = super::compile(SOURCE, windows::core::s!("ps"), windows::core::s!("ps_5_1"))?;
        // SAFETY: plain object creation; the bytecode lives through the
        // calls, and the root signature is inside it.
        unsafe {
            let root: ID3D12RootSignature = device.CreateRootSignature(0, &ps).map_err(|e| {
                tracing::warn!(error = %e, "the scaler's root signature");
                e
            })?;
            let mut desc = D3D12_GRAPHICS_PIPELINE_STATE_DESC {
                pRootSignature: std::mem::transmute_copy(&root),
                VS: D3D12_SHADER_BYTECODE {
                    pShaderBytecode: vs.as_ptr().cast(),
                    BytecodeLength: vs.len(),
                },
                PS: D3D12_SHADER_BYTECODE {
                    pShaderBytecode: ps.as_ptr().cast(),
                    BytecodeLength: ps.len(),
                },
                BlendState: D3D12_BLEND_DESC {
                    AlphaToCoverageEnable: false.into(),
                    IndependentBlendEnable: false.into(),
                    RenderTarget: [D3D12_RENDER_TARGET_BLEND_DESC {
                        BlendEnable: false.into(),
                        LogicOpEnable: false.into(),
                        SrcBlend: D3D12_BLEND_ONE,
                        DestBlend: D3D12_BLEND_ZERO,
                        BlendOp: D3D12_BLEND_OP_ADD,
                        SrcBlendAlpha: D3D12_BLEND_ONE,
                        DestBlendAlpha: D3D12_BLEND_ZERO,
                        BlendOpAlpha: D3D12_BLEND_OP_ADD,
                        LogicOp: D3D12_LOGIC_OP_NOOP,
                        RenderTargetWriteMask: D3D12_COLOR_WRITE_ENABLE_ALL.0 as u8,
                    }; 8],
                },
                RasterizerState: D3D12_RASTERIZER_DESC {
                    FillMode: D3D12_FILL_MODE_SOLID,
                    CullMode: D3D12_CULL_MODE_NONE,
                    DepthClipEnable: true.into(),
                    ..Default::default()
                },
                DepthStencilState: D3D12_DEPTH_STENCIL_DESC {
                    DepthEnable: false.into(),
                    StencilEnable: false.into(),
                    ..Default::default()
                },
                SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
                SampleMask: u32::MAX,
                PrimitiveTopologyType: D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE,
                NumRenderTargets: 1,
                DSVFormat: DXGI_FORMAT_UNKNOWN,
                ..Default::default()
            };
            desc.RTVFormats[0] = format;
            let pso: ID3D12PipelineState = device.CreateGraphicsPipelineState(&desc).map_err(|e| {
                tracing::warn!(error = %e, "the scaler's pipeline state");
                e
            })?;
            let heap: ID3D12DescriptorHeap = device.CreateDescriptorHeap(&D3D12_DESCRIPTOR_HEAP_DESC {
                Type: D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
                NumDescriptors: 1,
                Flags: D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
                NodeMask: 0,
            })?;
            Ok(Scale { pso, root, heap })
        }
    }

    /// Draws `from` (whose format is `from_format`), scaled to fill `to`
    /// (a render target of the swap chain's size), on `list`: `to` is left in
    /// the render target state, `from` in the pixel shader resource state.
    pub(super) fn draw(
        &self,
        device: &ID3D12Device,
        list: &ID3D12GraphicsCommandList,
        from: &ID3D12Resource,
        from_format: DXGI_FORMAT,
        to_rtv: D3D12_CPU_DESCRIPTOR_HANDLE,
        (width, height): (u32, u32),
    ) {
        // SAFETY: a live source texture, a view of our one-slot heap, and an
        // open list.
        unsafe {
            device.CreateShaderResourceView(
                from,
                Some(&D3D12_SHADER_RESOURCE_VIEW_DESC {
                    Format: from_format,
                    ViewDimension: D3D12_SRV_DIMENSION_TEXTURE2D,
                    Shader4ComponentMapping: D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING,
                    Anonymous: D3D12_SHADER_RESOURCE_VIEW_DESC_0 {
                        Texture2D: D3D12_TEX2D_SRV {
                            MostDetailedMip: 0,
                            MipLevels: 1,
                            PlaneSlice: 0,
                            ResourceMinLODClamp: 0.0,
                        },
                    },
                }),
                self.heap.GetCPUDescriptorHandleForHeapStart(),
            );
            list.SetDescriptorHeaps(&[Some(self.heap.clone())]);
            list.SetGraphicsRootSignature(&self.root);
            list.SetPipelineState(&self.pso);
            list.SetGraphicsRootDescriptorTable(0, self.heap.GetGPUDescriptorHandleForHeapStart());
            list.OMSetRenderTargets(1, Some(&to_rtv), false, None);
            list.RSSetViewports(&[D3D12_VIEWPORT {
                TopLeftX: 0.0,
                TopLeftY: 0.0,
                Width: width as f32,
                Height: height as f32,
                MinDepth: 0.0,
                MaxDepth: 1.0,
            }]);
            list.RSSetScissorRects(&[windows::Win32::Foundation::RECT {
                left: 0,
                top: 0,
                right: width as i32,
                bottom: height as i32,
            }]);
            list.IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            list.DrawInstanced(3, 1, 0, 0);
        }
    }
}
