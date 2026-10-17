///|
/// Planning failures carry a stable code and an optional MCU byte address.
pub(all) suberror UpdateError {
  UpdateError(String, String, UInt64?)
} derive(Debug)

///|
/// Half-open target policy interval, independent of the input record format.
pub(all) struct Window {
  name : String
  start : UInt64
  end_exclusive : UInt64
} derive(Eq, Debug)

///|
/// Explicit erase geometry. Adjacent sectors need not have equal sizes.
pub(all) struct Sector {
  name : String
  start : UInt64
  size : Int
} derive(Eq, Debug)

///|
/// NOR model: erased byte 0xFF; programming can clear bits only.
/// An update is a sparse overlay; omitted addresses retain baseline bytes.
pub(all) struct TargetProfile {
  name : String
  program_unit : Int
  sectors : Array[Sector]
  writable : Array[Window]
  protected_ranges : Array[Window]
  max_plan_bytes : Int
} derive(Debug)

///|
priv struct ProgramUnit {
  address : UInt64
  data : Bytes
}

///|
priv struct SectorUpdate {
  sector : Sector
  before : Bytes
  after : Bytes
  erase : Bool
  programs : Array[ProgramUnit]
  changed : Int
}

///|
/// Immutable plan snapshot. Only the planner can construct operations.
pub struct UpdatePlan {
  priv target : String
  priv unit : Int
  priv updates : Array[SectorUpdate]
}

///|
pub fn UpdatePlan::sector_count(self : UpdatePlan) -> Int {
  self.updates.length()
}

///|
pub fn UpdatePlan::erase_count(self : UpdatePlan) -> Int {
  self.updates.filter(s => s.erase).length()
}

///|
pub fn UpdatePlan::changed_bytes(self : UpdatePlan) -> Int {
  self.updates.fold(init=0, (total, s) => total + s.changed)
}

///|
pub fn UpdatePlan::program_bytes(self : UpdatePlan) -> Int {
  self.updates.fold(init=0, (total, s) => {
    total + s.programs.length() * self.unit
  })
}

///|
fn address_text(address : UInt64) -> String {
  "0x" + address.to_string(radix=16)
}

///|
/// Actual dependency use: record parsing and sparse image construction belong
/// to firmware-image-toolkit, not to MoonFirmware's legacy compatibility code.
pub fn parse_update_image(
  text : String,
) -> @image.FirmwareImage raise UpdateError {
  match @image.parse_firmware_image(text) {
    Ok(parsed) => parsed.image()
    Err(error) =>
      raise UpdateError(
        "InputFormat",
        error.code() + ": " + error.message() + " (line \{error.line_index()})",
        None,
      )
  }
}

///|
fn read_sector(
  image : @image.FirmwareImage,
  sector : Sector,
) -> Bytes raise UpdateError {
  match
    image.read_range(sector.start, sector.size, RejectMissing, sector.size) {
    Ok(bytes) => bytes
    Err(_) =>
      raise UpdateError(
        "MissingBaseline",
        "complete observed bytes required for affected sector " + sector.name,
        Some(sector.start),
      )
  }
}
