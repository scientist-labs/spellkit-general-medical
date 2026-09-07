# frozen_string_literal: true

require_relative "../pipeline/english_merge"

RSpec.describe Pipeline::EnglishMerge do
  # A miniature English list standing in for spellkit's en-80k.
  let(:english) do
    file = Tempfile.new(["en", ".txt"])
    file.write("the 1000000\nof 500000\ncell 20000\nrare 100\n")
    file.flush
    file
  end

  subject(:merge) { described_class.new(english_path: english.path, low_percentile: 25, high_percentile: 75) }

  after { english.close! }

  it "lifts domain frequencies into the English band instead of leaving them at the bottom" do
    # Raw domain frequencies (1..1000) sit far below even the rarest English word, which is
    # what would make every domain term unreachable as a correction target.
    merged = merge.merge([["acetaminophen", 1000], ["obscuridrug", 1]]).to_h

    expect(merged["obscuridrug"]).to be >= merge.stats[:band_low]
    expect(merged["acetaminophen"]).to be <= merge.stats[:band_high]
  end

  it "preserves the domain's own ordering through the rescale" do
    merged = merge.merge([["common", 1000], ["middling", 100], ["rare", 1]]).to_h

    expect(merged["common"]).to be > merged["middling"]
  end

  it "keeps every English word" do
    merged = merge.merge([["acetaminophen", 10]]).to_h

    expect(merged).to include("the", "of", "cell")
    expect(merged["the"]).to eq(1_000_000)
  end

  it "lets a common English word keep its weight when a domain term shares the spelling" do
    # "cell" is an everyday word first and a biology term second; demoting it to the domain
    # scale would make ordinary text correct badly.
    merged = merge.merge([["cell", 1]]).to_h

    expect(merged["cell"]).to eq(20_000)
    expect(merge.stats[:overlap]).to eq(1)
  end

  it "reports the band it used, since that band is the policy" do
    merge.merge([["x", 1]])

    expect(merge.stats[:band_low]).to be < merge.stats[:band_high]
  end
end
