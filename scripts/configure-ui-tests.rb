require 'xcodeproj'

# Generate a CI-only test target without changing the team's Xcode project.
project_path = 'Shallpick.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |target| target.name == 'Shallpick' }
target = project.new_target(:ui_test_bundle, 'ShallpickUITests', :ios, '26.0')
target.add_dependency(app)
group = project.main_group.new_group('UITests', 'UITests')
target.add_file_references([group.new_file('DemoFlowTests.swift')])
target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_NAME' => 'ShallpickUITests',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.shallpick.demo.uitests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'TEST_TARGET_NAME' => 'Shallpick',
    'SWIFT_VERSION' => '6.0',
    'CODE_SIGNING_ALLOWED' => 'NO',
    'TARGETED_DEVICE_FAMILY' => '1'
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(target)
scheme.save_as(project_path, 'ShallpickDemoCI', true)
