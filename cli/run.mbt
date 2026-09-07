///|
/// Execute a validated request. Protocol and image operations stay in libraries.
pub async fn run(request : Request) -> Int {
  match request {
    Help(command) => {
      @stdio.stdout.write(help(command))
      0
    }
    Version => {
      @stdio.stdout.write("moon-firmware 0.1.0\n")
      0
    }
    Run(config) => {
      let images = []
      for path in config.inputs {
        images.push(read_input(path, config))
      }
      let image = images[0]
      match config.command {
        "inspect" => {
          let stats = @firmware.inspect_image(image)
          @stdio.stdout.write(
            if config.json {
              statistics_json(stats).stringify() + "\n"
            } else {
              stats.render() + "\n"
            },
          )
          show_warnings(image.warnings)
          0
        }
        "verify" => {
          @stdio.stdout.write(
            "Verified " +
            image.metadata.source_format.label() +
            ": \{image.memory.payload_size()} payload bytes; checksum " +
            @firmware.format_checksum(image.metadata.checksum_status) +
            "\n",
          )
          show_warnings(image.warnings)
          0
        }
        "diff" => {
          let diff = @firmware.diff_images(image, images[1])
          @stdio.stdout.write(
            if config.json {
              diff_json(diff).stringify() + "\n"
            } else {
              diff.render()
            },
          )
          for item in images {
            show_warnings(item.warnings)
          }
          if diff.is_equal() {
            0
          } else {
            1
          }
        }
        _ => {
          let processed = match config.command {
            "merge" =>
              @firmware.merge_images(
                images,
                policy=config.parse_options.overlap,
                entry_policy=config.entry_policy,
              )
            "extract" => @firmware.extract_range(image, config.range.unwrap())
            _ => image
          }
          let converted = @firmware.convert(processed, config.convert_options)
          write_output(config.output.unwrap(), converted.bytes, config.force)
          let message = match config.command {
            "merge" =>
              "Merged \{images.length()} images -> " +
              config.convert_options.format.label()
            "extract" =>
              "Extracted " +
              config.range.unwrap().render() +
              " -> " +
              config.convert_options.format.label()
            _ =>
              "Converted " +
              image.metadata.source_format.label() +
              " -> " +
              config.convert_options.format.label()
          }
          @stdio.stdout.write(message + "\n")
          if converted.binary_base is Some(base) {
            @stdio.stdout.write(
              "Binary base: " + @model.hex_address(base) + "\n",
            )
          }
          show_warnings(converted.warnings)
          0
        }
      }
    }
  }
}

///|
/// JSON addresses are exact 32-bit values; ranges use an exclusive end.
fn statistics_json(stats : @firmware.ImageStatistics) -> Json {
  {
    "format": stats.format.label().to_json(),
    "lowest_address": stats.lowest_address.to_json(),
    "highest_address": stats.highest_address.to_json(),
    "address_span": stats.address_span.to_json(),
    "payload_bytes": stats.payload_bytes.to_json(),
    "segment_count": stats.segment_count.to_json(),
    "gap_count": stats.gap_count.to_json(),
    "gap_bytes": stats.gap_bytes.to_json(),
    "entry_point": @firmware.format_entry(stats.entry).to_json(),
    "checksum_status": @firmware.format_checksum(stats.checksum_status).to_json(),
    "record_count": stats.record_count.to_json(),
    "record_counts": stats.record_counts.to_json(),
    "warning_count": stats.warning_count.to_json(),
  }
}

///|
fn ranges_json(ranges : Array[@model.AddressRange]) -> Json {
  ranges
  .map(r => {
    ({ "start": r.start.to_json(), "end_exclusive": r.end.to_json() } : Json)
  })
  .to_json()
}

///|
fn diff_json(diff : @firmware.FirmwareDiff) -> Json {
  {
    "identical_bytes": diff.identical_bytes.to_json(),
    "changed_bytes": diff.changed_bytes.to_json(),
    "added_bytes": diff.added_bytes.to_json(),
    "removed_bytes": diff.removed_bytes.to_json(),
    "entry_changed": diff.entry_changed.to_json(),
    "changed": ranges_json(diff.changed),
    "only_left": ranges_json(diff.only_left),
    "only_right": ranges_json(diff.only_right),
  }
}
