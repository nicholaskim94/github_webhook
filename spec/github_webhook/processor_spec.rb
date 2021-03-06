require 'spec_helper'

module GithubWebhook
  describe Processor do

    class Request
      attr_accessor :headers, :body

      def initialize
        @headers = {}
        @body = StringIO.new
      end
    end

    class ControllerWithoutSecret
      ### Helpers to mock ActionController::Base behavior
      attr_accessor :request, :pushed

      def self.skip_before_filter(*args); end
      def self.before_filter(*args); end
      def head(*args); end
      ###

      include GithubWebhook::Processor

      def github_push(payload)
        @pushed = payload[:foo]
      end
    end

    class Controller < ControllerWithoutSecret
      def webhook_secret(payload)
        "secret"
      end
    end

    let(:controller) do
      controller = Controller.new
      controller.request = Request.new
      controller
    end

    let(:controller_without_secret) do
      ControllerWithoutSecret.new
    end

    describe "#create" do
      it "raises an error when secret is not defined" do
        expect { controller_without_secret.send :authenticate_github_request! }.to raise_error(Processor::UnspecifiedWebhookSecretError)
      end

      it "calls the #push method in controller (json)" do
        controller.request.body = StringIO.new({ :foo => "bar" }.to_json.to_s)
        controller.request.headers['X-Hub-Signature'] = "sha1=52b582138706ac0c597c315cfc1a1bf177408a4d"
        controller.request.headers['X-GitHub-Event'] = 'push'
        controller.request.headers['Content-Type'] = 'application/json'
        controller.send :authenticate_github_request!  # Manually as we don't have the before_filter logic in our Mock object
        controller.create
        expect(controller.pushed).to eq "bar"
      end

      it "calls the #push method (x-www-form-urlencoded encoded)" do
        body = "payload=" + CGI::escape({ :foo => "bar" }.to_json.to_s)
        controller.request.body = StringIO.new(body)
        controller.request.headers['X-Hub-Signature'] = "sha1=6986874ecdf710b04de7ef5a040161d41687407a"
        controller.request.headers['X-GitHub-Event'] = 'push'
        controller.request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        controller.send :authenticate_github_request!  # Manually as we don't have the before_filter logic in our Mock object
        controller.create
        expect(controller.pushed).to eq "bar"
      end

      it "raises an error when signature does not match" do
        controller.request.body = StringIO.new({ :foo => "bar" }.to_json.to_s)
        controller.request.headers['X-Hub-Signature'] = "sha1=FOOBAR"
        controller.request.headers['X-GitHub-Event'] = 'push'
        controller.request.headers['Content-Type'] = 'application/json'
        expect { controller.send :authenticate_github_request! }.to raise_error(Processor::SignatureError)
      end

      it "raises an error when the github event method is not implemented" do
        controller.request.headers['X-GitHub-Event'] = 'deployment'
        controller.request.headers['Content-Type'] = 'application/json'
        expect { controller.create }.to raise_error(NoMethodError)
      end

      it "raises an error when the github event is not in the whitelist" do
        controller.request.headers['X-GitHub-Event'] = 'fake_event'
        controller.request.headers['Content-Type'] = 'application/json'
        expect { controller.send :check_github_event! }.to raise_error(Processor::UnsupportedGithubEventError)
      end

      it "raises an error when the content type is not correct" do
        controller.request.body = StringIO.new({ :foo => "bar" }.to_json.to_s)
        controller.request.headers['X-Hub-Signature'] = "sha1=52b582138706ac0c597c315cfc1a1bf177408a4d"
        controller.request.headers['X-GitHub-Event'] = 'ping'
        controller.request.headers['Content-Type'] = 'application/xml'
        expect { controller.send :authenticate_github_request! }.to raise_error(Processor::UnsupportedContentTypeError)
      end
    end
  end
end
