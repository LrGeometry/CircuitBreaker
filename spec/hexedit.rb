require_relative "../visual/memory_editor.rb"

RSpec.describe "CacheEntry::Edit" do
  Edit = Visual::MemoryEditorPanel::CacheEntry::Edit
  
  describe "#apply" do
    it "applies patches when patch fits" do
      data  = "00000000"
      patch =   "1234"

      edit = Edit.new(2, patch)
      expect(edit.apply(data, 0)).to eq "00123400"
    end

    it "will cut off the beginning of patch when appropriate" do
      data  =   "00000000"
      patch = "1234"

      edit = Edit.new(0, patch)
      expect(edit.apply(data, 2)).to eq "34000000"
    end

    it "will cut off the end of patch when appropriate" do
      data  = "00000000"
      patch =       "1234"

      edit = Edit.new(6, patch)
      expect(edit.apply(data, 0)).to eq "00000012"
    end

    it "will cut off both ends of patch" do
      data  =   "0000"
      patch = "12345678"

      edit = Edit.new(0, patch)
      expect(edit.apply(data, 2)).to eq "3456"
    end

    it "will not apply patch out of range after" do
      data  = "0000"
      patch =      "1234"

      edit = Edit.new(5, patch)
      expect(edit.apply(data, 0)).to eq "0000"
    end
    
    it "will not apply patch out of range before" do
      data  =      "0000"
      patch = "1234"

      edit = Edit.new(0, patch)
      expect(edit.apply(data, 5)).to eq "0000"
    end
  end

  describe "#insert_next and #attempt_merge_next" do
    def merge_to(a_off, a, b_off, b, result)
      a = Edit.new(a_off, a)
      b = Edit.new(b_off, b)
      a.insert_next(b)
      expect(a.next_edit).to be_nil
      expect(a.base).to eq a_off
      expect(a.patch).to eq result
    end
    
    it "will merge adjacent edits properly" do
      merge_to(0, "aaa",
               3, "bbb",
               "aaabbb")
    end
    
    it "will merge overlapping edits properly" do
      merge_to(0, "aaa",
               2, "bbb",
              "aabbb")
    end

    it "will merge sub-edits properly" do
      merge_to(0, "aaa",
               1, "b",
               "aba")
    end

    it "will merge edits starting in the sample place properly" do
      merge_to(0, "aaa",
               0, "bb",
               "bba")
    end
    
    it "will be clobbered by big edits at the same base" do
      merge_to(0, "aaa",
               0, "bbbb",
               "bbbb")
    end
    
    it "will not merge edits with a gap" do
      a = Edit.new(0, "aaa")
      b = Edit.new(4, "bbb")
      a.insert_next(b)
      expect(a.next_edit).to be b
      expect(a.base).to eq 0
      expect(a.patch).to eq "aaa"
      expect(b.next_edit).to be_nil
      expect(b.base).to eq 4
      expect(b.patch).to eq "bbb"
    end
  end
end
