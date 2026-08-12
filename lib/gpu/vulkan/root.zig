//! The native Vulkan presentation path.
//!
//! Split into four parts along the line that decides what can be tested. `abi`
//! is the structure layouts the host driver reads; `selection` is every choice
//! made from what the driver reported; `frame` is the ownership and health
//! bookkeeping between frames; `presenter` is the thin remainder that actually
//! calls the driver. The first three run anywhere — no window, no runloop, no
//! MoltenVK — which is where the arithmetic that silently corrupts a frame is
//! allowed to be wrong only once.

pub const abi = @import("abi.zig");
pub const selection = @import("selection.zig");
pub const frame = @import("frame.zig");
pub const presenter = @import("presenter.zig");

pub const Presenter = presenter.Presenter;
pub const Stage = presenter.Stage;
pub const Source = presenter.Source;
pub const CpuImage = presenter.CpuImage;
pub const FrameReport = presenter.FrameReport;
pub const Report = presenter.Report;
pub const SymbolResolver = presenter.SymbolResolver;
pub const Health = frame.Health;

test {
    _ = abi;
    _ = selection;
    _ = frame;
    _ = presenter;
}
