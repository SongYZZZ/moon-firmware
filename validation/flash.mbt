///|
/// Bounded whole-page programming settings. Page boundaries are aligned to
/// address zero. erase_value must be chosen explicitly for the target device.
/// allowed_range, when present, must contain every entire touched page.
pub(all) struct FlashOptions {
  page_size : Int
  erase_value : Byte
  max_pages : Int
  max_output_bytes : Int
  allowed_range : @model.AddressRange?
} derive(Eq, Debug)

///|
/// Plan with an explicit erase value and conservative allocation budgets.
/// Page size must be a power of two from 1 through 1048576 bytes.
pub fn FlashOptions::new(page_size : Int, erase_value : Byte) -> FlashOptions {
  {
    page_size,
    erase_value,
    max_pages: 65536,
    max_output_bytes: 16 * 1024 * 1024,
    allowed_range: None,
  }
}

///|
/// One complete programming page. source_ranges identifies original occupied
/// bytes so applications can distinguish payload from erased padding, even
/// when payload bytes happen to equal the erase value.
pub struct FlashPage {
  range : @model.AddressRange
  data : Bytes
  source_ranges : Array[@model.AddressRange]
} derive(Eq, Debug)

///|
/// Deterministic pages sorted by address. Only touched pages are included;
/// untouched address gaps are not erased or represented in this plan.
/// This is a data plan, not a flash programmer or device erase instruction.
pub struct FlashPlan {
  pages : Array[FlashPage]
  payload_bytes : Int
  output_bytes : Int
  erase_fill_bytes : Int
  page_size : Int
  erase_value : Byte
} derive(Eq, Debug)

///|
/// Build complete bytes only for pages containing occupied firmware addresses.
/// Missing bytes within touched pages use erase_value, including bytes outside
/// image bounds. This deliberately does not preserve existing device content:
/// callers must obtain/merge that content first when retention is required.
/// Page count, allocation limits and permitted programming bounds are checked
/// before page buffers are allocated. The input image is never modified.
pub fn plan_flash_pages(
  image : @model.FirmwareImage,
  options : FlashOptions,
) -> FlashPlan raise @model.FirmwareError {
  if !valid_alignment(options.page_size) {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "flash page size must be a power of two between 1 and 1048576",
      ),
    )
  }
  if options.max_pages < 0 ||
    options.max_pages > 65536 ||
    options.max_output_bytes < 0 ||
    options.max_output_bytes > 64 * 1024 * 1024 {
    raise @model.FirmwareError(
      @model.diagnostic(
        InvalidOption,
        "flash limits must fit 65536 pages and 64 MiB output",
      ),
    )
  }
  let segments = image.memory.segments()
  let page_size = options.page_size.to_int64()
  let touched = touched_page_ranges(segments, page_size)
  let mut page_count = 0L
  for range in touched {
    if options.allowed_range is Some(allowed) {
      if range.start < allowed.start || range.end > allowed.end {
        raise @model.FirmwareError(
          @model.diagnostic(
            InvalidRange,
            "complete flash pages exceed the permitted programming range",
            address=range.start,
            end_address=range.end - 1L,
          ),
        )
      }
    }
    page_count += range.length() / page_size
  }
  if page_count > options.max_pages.to_int64() {
    raise @model.FirmwareError(
      @model.diagnostic(
        ResourceLimit,
        "flash plan needs \{page_count} pages; limit is \{options.max_pages}",
      ),
    )
  }
  let output_bytes = page_count * page_size
  if output_bytes > options.max_output_bytes.to_int64() {
    raise @model.FirmwareError(
      @model.diagnostic(
        ResourceLimit,
        "flash plan needs \{output_bytes} bytes; limit is \{options.max_output_bytes}",
      ),
    )
  }
  let pages = []
  let mut first_segment = 0
  for extent in touched {
    let mut start = extent.start
    while start < extent.end {
      let range = @model.AddressRange::new(start, start + page_size)
      while first_segment < segments.length() &&
            segments[first_segment].range().end <= start {
        first_segment += 1
      }
      let data = Array::make(options.page_size, options.erase_value)
      let source_ranges = []
      let mut index = first_segment
      while index < segments.length() && segments[index].start < range.end {
        let segment = segments[index]
        if segment.range().intersection(range) is Some(source) {
          source_ranges.push(source)
          let source_offset = (source.start - segment.start).to_int()
          let page_offset = (source.start - range.start).to_int()
          for offset in 0..<source.length().to_int() {
            data[page_offset + offset] = segment.data[source_offset + offset]
          }
        }
        index += 1
      }
      pages.push({ range, data: Bytes::from_array(data), source_ranges, })
      start += page_size
    }
  }
  {
    pages,
    payload_bytes: image.memory.payload_size(),
    output_bytes: output_bytes.to_int(),
    erase_fill_bytes: output_bytes.to_int() - image.memory.payload_size(),
    page_size: options.page_size,
    erase_value: options.erase_value,
  }
}

///|
// Group page extents before expansion: adjacent/overlapping page intervals
// coalesce, but sparse gaps with no occupied page remain absent. Arithmetic is
// Int64 and page sizes divide the 32-bit address space, including its last page.
fn touched_page_ranges(
  segments : Array[@model.MemorySegment],
  page_size : Int64,
) -> Array[@model.AddressRange] raise @model.FirmwareError {
  let ranges : Array[@model.AddressRange] = []
  for segment in segments {
    let start = segment.start - segment.start % page_size
    let last = segment.range().end - 1L
    let end = last - last % page_size + page_size
    if ranges.last() is Some(previous) {
      if start <= previous.end {
        ranges[ranges.length() - 1] = @model.AddressRange::new(
          previous.start,
          previous.end.max(end),
        )
        continue
      }
    }
    ranges.push(@model.AddressRange::new(start, end))
  }
  ranges
}

///|
/// Summarize programmed addresses and padding without rendering payload bytes.
/// The manifest helps inspect an erase plan before any device is contacted.
pub fn FlashPlan::render_manifest(self : FlashPlan) -> String {
  let out = StringBuilder()
  out.write_string("Flash pages: \{self.pages.length()}\n")
  out.write_string("Page size: \{self.page_size} bytes\n")
  out.write_string("Payload: \{self.payload_bytes} bytes\n")
  out.write_string("Output: \{self.output_bytes} bytes\n")
  out.write_string("Erase padding: \{self.erase_fill_bytes} bytes\n")
  out.write_string(
    "Erase value: 0x" +
    self.erase_value.to_int().to_string(radix=16).to_upper().pad_start(2, '0') +
    "\n",
  )
  for page in self.pages {
    let mut occupied = 0L
    for source in page.source_ranges {
      occupied += source.length()
    }
    out.write_string(page.range.render() + ": \{occupied} payload bytes\n")
  }
  out.to_string()
}
