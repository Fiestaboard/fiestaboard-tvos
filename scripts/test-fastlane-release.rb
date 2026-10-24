#!/usr/bin/env ruby
require "minitest/autorun"

# Exercise our lane's action boundary without invoking Apple's service. Deliver's
# build_number selects an existing upload and conflicts with an IPA upload.
class ReleaseLaneHarness
  attr_reader :delivery
  def default_platform(*); end
  def platform(*); yield; end
  def desc(*); end
  def lane(*); yield; end
  def app_store_connect_api_key(**); { key_id: "test" }; end
  def deliver(**options)
    raise "build_number selects an existing build and conflicts with ipa" if options[:build_number] && options[:ipa]
    @delivery = options
  end
end

class ReleaseLaneTest < Minitest::Test
  def evaluate_lane(submit)
    values = {"ASC_KEY_ID"=>"test", "ASC_ISSUER_ID"=>"test", "ASC_KEY_PATH"=>"/tmp/test.p8",
              "RELEASE_VERSION"=>"1.0.1", "RELEASE_BUILD_NUMBER"=>"12.1",
              "RELEASE_IPA"=>"/tmp/build.ipa", "SUBMIT_FOR_REVIEW"=>submit}
    previous = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    harness = ReleaseLaneHarness.new
    harness.instance_eval(File.read(File.expand_path("../fastlane/Fastfile", __dir__)))
    harness.delivery
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_upload_only_requests_binary_delivery_without_review
    delivery = evaluate_lane("false")
    assert_equal "/tmp/build.ipa", delivery[:ipa]
    assert_equal false, delivery[:submit_for_review]
  end

  def test_public_release_uploads_then_requests_review_and_automatic_release
    delivery = evaluate_lane("true")
    assert_equal "/tmp/build.ipa", delivery[:ipa]
    assert_equal true, delivery[:submit_for_review]
    assert_equal true, delivery[:automatic_release]
  end
end
