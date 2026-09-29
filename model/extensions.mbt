///|
/// Keep derived comparison operations available as explicit public methods.
pub extend AddressRange with Eq::{not_equal, equal}

///|
pub extend AddressRange with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Format with Eq::{not_equal, equal}

///|
pub extend Format with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ErrorCode with Eq::{not_equal, equal}

///|
pub extend ErrorCode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{not_equal, equal}

///|
pub extend Diagnostic with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FirmwareError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ParseMode with Eq::{not_equal, equal}

///|
pub extend ParseMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OverlapPolicy with Eq::{not_equal, equal}

///|
pub extend OverlapPolicy with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ParseOptions with Eq::{not_equal, equal}

///|
pub extend ParseOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EntryPoint with Eq::{not_equal, equal}

///|
pub extend EntryPoint with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChecksumStatus with Eq::{not_equal, equal}

///|
pub extend ChecksumStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Metadata with Eq::{not_equal, equal}

///|
pub extend Metadata with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MemorySegment with Eq::{not_equal, equal}

///|
pub extend MemorySegment with @moonbitlang/core/debug.Debug::{to_repr}
