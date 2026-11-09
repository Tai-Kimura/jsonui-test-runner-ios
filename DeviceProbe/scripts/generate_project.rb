#!/usr/bin/env ruby
# frozen_string_literal: true

# DeviceProbe.xcodeproj (generated, gitignored): SliderProbeApp and the
# on-device arms that need a real SwiftUI control, linking this package as a
# local Swift package. Requires the 'xcodeproj' gem (ships with CocoaPods).
#
#   ruby DeviceProbe/scripts/generate_project.rb
#   xcodebuild test -project DeviceProbe/DeviceProbe.xcodeproj -scheme DeviceProbe \
#     -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath DeviceProbe/build/dd
require 'xcodeproj'

dir = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(dir, 'DeviceProbe.xcodeproj'))
target = '17.0'

app = project.new_target(:application, 'DeviceProbe', :ios, target)
app_group = project.main_group.new_group('App', 'App')
Dir[File.join(dir, 'App', '*.swift')].sort.each { |f| app.add_file_references([app_group.new_reference(f)]) }

tests = project.new_target(:ui_test_bundle, 'DeviceProbeUITests', :ios, target)
test_group = project.main_group.new_group('UITests', 'UITests')
Dir[File.join(dir, 'UITests', '*.swift')].sort.each { |f| tests.add_file_references([test_group.new_reference(f)]) }
tests.add_dependency(app)

package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = '..'
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.product_name = 'JsonUITestRunner'
tests.package_product_dependencies << product

project.targets.each do |t|
  t.build_configurations.each do |c|
    b = c.build_settings
    b['SWIFT_VERSION'] = '5.0'
    b['GENERATE_INFOPLIST_FILE'] = 'YES'
    b['CODE_SIGN_STYLE'] = 'Automatic'
    b['CODE_SIGNING_REQUIRED'] = 'NO'
    b['TARGETED_DEVICE_FAMILY'] = '1'
    b['IPHONEOS_DEPLOYMENT_TARGET'] = target
    b['CURRENT_PROJECT_VERSION'] = '1'
    b['MARKETING_VERSION'] = '1.0'
  end
end
app.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.jsonui.testrunner.DeviceProbe'
  c.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
tests.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.jsonui.testrunner.DeviceProbeUITests'
  c.build_settings['TEST_TARGET_NAME'] = 'DeviceProbe'
end
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(project.path, 'DeviceProbe', true)
puts "generated #{project.path}"
