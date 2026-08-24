//! The contract type vocabulary moved to `pkg/common/abi/host-contract-catalogue`.
//!
//! `ContractKind`, `ResolutionStrategy` and `MatchPattern` describe the host
//! ABI surface Rosette was built against — a build-time fact — and they are
//! declared beside the catalogue that uses them so the two cannot drift. This
//! file stays as the module-local spelling every existing consumer imports.

const catalogue = @import("host_contract_catalogue");

pub const ContractKind = catalogue.ContractKind;
pub const ResolutionStrategy = catalogue.ResolutionStrategy;
pub const MatchPattern = catalogue.MatchPattern;
pub const Contract = catalogue.Contract;
pub const Parameter = catalogue.Parameter;
pub const ReturnPolicy = catalogue.ReturnPolicy;
