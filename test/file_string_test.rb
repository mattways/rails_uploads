require 'test_helper'

class FileStringTest < ActiveSupport::TestCase

  setup :create_file

  test "methods should work properly" do

    # Basic tests

    assert @file.exists?
    assert_equal 11, @file.size
    assert_equal '.txt', @file.extname
    assert_equal "/uploads/#{@file.filename}", @file.path
    assert_equal Rails.root.join('public', 'uploads', @file.filename), @file.realpath
    
    # Delete tests

    uploads_path = Rails.root.join('public', 'uploads', @file.filename)
    @file.delete
    assert !::File.exists?(uploads_path)
    assert !@file.exists?

  end

  protected

  def create_file
    filename = 'doc.txt'
    FileUtils.cp File.join(ActiveSupport::TestCase.fixture_path, filename), Rails.root.join('public', 'uploads', filename)
    @file = RailsUploads::Types::File.new(filename)
  end

end