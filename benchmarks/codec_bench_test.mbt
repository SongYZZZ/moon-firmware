///|
fn dense_image(size : Int) -> @model.FirmwareImage raise {
  let binary = @model.FirmwareImage::from_binary(
    Bytes::makei(size, i => (i % 251).to_byte()),
    0x08000000L,
  )
  { ..binary, entry: Some(@model.EntryPoint::Linear(0x08000101L)), }
}

///|
test "100 KiB codec" (b : @bench.T) {
  let image = dense_image(100 * 1024)
  let hex = @ihex.encode(image)
  let srec = @srec.encode(image)
  b.bench(
    name="HEX parse 100 KiB",
    () => b.keep(try! @ihex.parse_document(hex)),
    count=5,
  )
  b.bench(
    name="HEX write 100 KiB",
    () => b.keep(try! @ihex.encode(image)),
    count=5,
  )
  b.bench(
    name="SREC parse 100 KiB",
    () => b.keep(try! @srec.parse_document(srec)),
    count=5,
  )
  b.bench(
    name="SREC write 100 KiB",
    () => b.keep(try! @srec.encode(image)),
    count=5,
  )
}

///|
test "1 MiB codec" (b : @bench.T) {
  let image = dense_image(1024 * 1024)
  let hex = @ihex.encode(image)
  let srec = @srec.encode(image)
  b.bench(
    name="HEX parse 1 MiB",
    () => b.keep(try! @ihex.parse_document(hex)),
    count=5,
  )
  b.bench(
    name="HEX write 1 MiB",
    () => b.keep(try! @ihex.encode(image)),
    count=5,
  )
  b.bench(
    name="SREC parse 1 MiB",
    () => b.keep(try! @srec.parse_document(srec)),
    count=5,
  )
  b.bench(
    name="SREC write 1 MiB",
    () => b.keep(try! @srec.encode(image)),
    count=5,
  )
}

///|
test "sparse and small records" (b : @bench.T) {
  let memory = @model.MemoryMap::new()
  for i in 0..<1024 {
    memory.insert(i.to_int64() * 0x400000L, Bytes::make(100, i.to_byte()))
  }
  let sparse = { ..@model.FirmwareImage::new(), memory, }
  let sparse_text = @ihex.encode(sparse)
  b.bench(
    name="HEX sparse 1024 segments across 4 GiB",
    () => b.keep(try! @ihex.parse_document(sparse_text)),
    count=5,
  )
  let dense = dense_image(100 * 1024)
  let small = @ihex.encode(dense, options={
    ..@ihex.WriterOptions::default(),
    data_length: 1,
  })
  b.bench(
    name="HEX 102400 one-byte records",
    () => b.keep(try! @ihex.parse_document(small)),
    count=5,
  )
}
