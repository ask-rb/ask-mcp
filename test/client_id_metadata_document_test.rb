# frozen_string_literal: true

require_relative "test_helper"

class ClientIdMetadataDocumentTest < Minitest::Test
  def build(**kwargs)
    Ask::MCP::Auth::ClientIdMetadataDocument.build(
      client_id: "https://app.example.com/oauth/client-metadata.json",
      client_name: "Example MCP Client",
      redirect_uris: ["http://127.0.0.1:3000/callback"],
      **kwargs
    )
  end

  def reason(doc, url: nil)
    Ask::MCP::Auth::ClientIdMetadataDocument.invalid_reason(doc, document_url: url)
  end

  def test_build_includes_required_fields
    doc = build
    assert_equal "https://app.example.com/oauth/client-metadata.json", doc["client_id"]
    assert_equal "Example MCP Client", doc["client_name"]
    assert_equal ["http://127.0.0.1:3000/callback"], doc["redirect_uris"]
    assert_equal "native", doc["application_type"], "CLI/native clients default to native"
  end

  def test_build_with_extra_fields_and_web_app_type
    doc = build(application_type: "web", client_uri: "https://app.example.com")
    assert_equal "web", doc["application_type"]
    assert_equal "https://app.example.com", doc["client_uri"]
  end

  def test_valid_document
    assert_nil reason(build)
  end

  def test_valid_document_matching_url
    url = "https://app.example.com/oauth/client-metadata.json"
    assert_nil reason(build, url: url)
  end

  def test_missing_required_fields
    doc = build
    doc.delete("client_name")
    assert_match(/client_name/, reason(doc))
  end

  def test_client_id_mismatch_with_document_url
    url = "https://app.example.com/oauth/client-metadata.json"
    doc = build(client_id: "https://evil.example.com/client.json")
    assert_match(/does not match document URL/, reason(doc, url: url))
  end

  def test_invalid_client_id_url_forms
    refute Ask::MCP::Auth::ClientIdMetadataDocument.valid_client_id_url?("http://app.example.com/client.json"),
           "http scheme is not allowed"
    refute Ask::MCP::Auth::ClientIdMetadataDocument.valid_client_id_url?("https://app.example.com"),
           "no path component is not allowed"
    refute Ask::MCP::Auth::ClientIdMetadataDocument.valid_client_id_url?("https://app.example.com/"),
           "root path is not allowed"
    assert Ask::MCP::Auth::ClientIdMetadataDocument.valid_client_id_url?("https://app.example.com/client.json")
  end

  def test_client_id_must_be_https_url
    doc = build(client_id: "not-a-url")
    assert_match(/https URL/, reason(doc))
  end

  def test_redirect_uris_must_be_non_empty
    doc = build(redirect_uris: [])
    assert_match(/redirect_uris/, reason(doc))
  end

  def test_invalid_application_type
    doc = build(application_type: "service")
    assert_match(/application_type/, reason(doc))
  end

  def test_non_hash_document_is_invalid
    assert_match(/JSON object/, reason("not a document"))
  end

  def test_round_trip_is_valid
    doc = build(client_uri: "https://app.example.com")
    assert_nil reason(doc)
  end
end
