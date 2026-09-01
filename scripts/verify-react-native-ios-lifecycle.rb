#!/usr/bin/env ruby

source_path = File.expand_path(
  ARGV.fetch(0, File.join(__dir__, "..", "adapters", "react-native", "ios", "LevixelView.swift"))
)
abort("Usage: #{$PROGRAM_NAME} [LevixelView.swift]") if ARGV.length > 1
abort("React Native iOS view source is missing: #{source_path}") unless File.file?(source_path)

source = File.read(source_path)
fabric_start = source.index("#if RCT_NEW_ARCH_ENABLED")
abort("React Native iOS view does not declare its Fabric lifecycle") unless fabric_start
fabric_end = source.index("#endif", fabric_start)
abort("React Native iOS Fabric lifecycle is not closed") unless fabric_end
fabric_source = source[fabric_start...fabric_end]

extract_body = lambda do |signature|
  signature_start = fabric_source.index(signature)
  abort("Missing Fabric lifecycle method: #{signature}") unless signature_start
  open_brace = fabric_source.index("{", signature_start + signature.length)
  abort("Malformed Fabric lifecycle method: #{signature}") unless open_brace

  depth = 0
  close_brace = nil
  fabric_source.each_char.with_index do |character, offset|
    next if offset < open_brace
    depth += 1 if character == "{"
    depth -= 1 if character == "}"
    if depth.zero?
      close_brace = offset
      break
    end
  end
  abort("Unclosed Fabric lifecycle method: #{signature}") unless close_brace
  fabric_source[(open_brace + 1)...close_brace]
end

expect_in_order = lambda do |label, body, *statements|
  cursor = -1
  statements.each do |statement|
    position = body.index(statement, cursor + 1)
    abort("#{label} must call #{statement}") unless position
    abort("#{label} lifecycle calls are out of order") if position <= cursor
    cursor = position
  end
end

mount_body = extract_body.call(
  "override func mountChildComponentView(_ childComponentView: UIView, index: Int)"
)
expect_in_order.call(
  "Fabric mount",
  mount_body,
  "super.mountChildComponentView(childComponentView, index: index)",
  "configureSourceView()"
)

unmount_body = extract_body.call(
  "override func unmountChildComponentView(_ childComponentView: UIView, index: Int)"
)
expect_in_order.call(
  "Fabric unmount",
  unmount_body,
  "clearConfiguredImageView()",
  "super.unmountChildComponentView(childComponentView, index: index)"
)

recycle_body = extract_body.call("override func prepareForRecycle()")
expect_in_order.call(
  "Fabric recycle",
  recycle_body,
  "clearConfiguredImageView()",
  "super.prepareForRecycle()"
)

puts "Verified symmetric React Native iOS Fabric mount, unmount, and recycle handling."
