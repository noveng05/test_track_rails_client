require 'rails_helper'

RSpec.describe TestTrack::CreateAliasJob do
  let(:params) { { existing_mixpanel_id: "fake_mixpanel_id", alias_id: "fake_visitor_id" } }

  subject { described_class.new(params) }

  it "blows up with empty existing_mixpanel_id" do
    expect { described_class.new(params.merge(existing_mixpanel_id: '')) }
      .to raise_error(/existing_mixpanel_id/)
  end

  it "blows up with empty alias_id" do
    expect { described_class.new(params.merge(alias_id: nil)) }
      .to raise_error(/alias_id/)
  end

  it "blows up with unknown opts" do
    expect { described_class.new(params.merge(extra_stuff: true)) }
      .to raise_error(/unknown opts/)
  end

  describe "#perform" do
    let(:mixpanel) { instance_double(Mixpanel::Tracker, alias: true) }
    before do
      allow(Mixpanel::Tracker).to receive(:new).and_return(mixpanel)
      ENV['MIXPANEL_TOKEN'] = 'fakefakefake'
    end

    it "configures mixpanel with the token" do
      subject.perform
      expect(Mixpanel::Tracker).to have_received(:new).with("fakefakefake")
    end

    it "sends mixpanel events" do
      subject.perform
      expect(mixpanel).to have_received(:alias).with("fake_visitor_id", "fake_mixpanel_id")
    end

    it "blows up if the mixpanel alias fails" do
      # mock mixpanel's HTTP call to get a bit more integration coverage for mixpanel.
      # this also ensures that this test breaks if mixpanel-ruby is upgraded, since new versions react differently to 500s
      allow(Mixpanel::Tracker).to receive(:new).and_call_original
      stub_request(:post, 'https://api.mixpanel.com/track').to_return(status: 500, body: "")

      expect { subject.perform }
        .to raise_error("mixpanel alias failed for existing_mixpanel_id: fake_mixpanel_id, alias_id: fake_visitor_id")

      expect(WebMock).to have_requested(:post, 'https://api.mixpanel.com/track')
    end
  end
end