module TestTrack
  module Controller
    extend ActiveSupport::Concern

    included do
      helper_method :test_track_session, :test_track_visitor
      around_action :manage_test_track_session
    end

    private

    def test_track_session
      @test_track_session ||= TestTrack::Session.new(self)
    end

    def test_track_visitor
      test_track_session.visitor
    end

    def manage_test_track_session
      test_track_session.manage do
        yield
      end
    end
  end
end