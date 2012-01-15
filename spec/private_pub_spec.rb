require "spec_helper"

describe PrivatePub do
  before(:each) do
    PrivatePub.reset_config
  end

  it "defaults server to nil" do
    PrivatePub.config[:server].should be_nil
  end

  it "defaults signature_expiration to nil" do
    PrivatePub.config[:signature_expiration].should be_nil
  end

  it "defaults subscription timestamp to current time in milliseconds" do
    time = Time.now
    Time.stub!(:now).and_return(time)
    PrivatePub.subscription[:timestamp].should == (time.to_f * 1000).round
  end

  it "loads a simple configuration file via load_config" do
    PrivatePub.load_config("spec/fixtures/private_pub.yml", "production")
    PrivatePub.config[:server].should == "http://example.com/faye"
    PrivatePub.config[:secret_token].should == "PRODUCTION_SECRET_TOKEN"
    PrivatePub.config[:signature_expiration].should == 600
  end

  it "raises an exception if an invalid environment is passed to load_config" do
    lambda {
      PrivatePub.load_config("spec/fixtures/private_pub.yml", :test)
    }.should raise_error ArgumentError
  end

  it "includes channel, server, and custom time in subscription" do
    PrivatePub.config[:server] = "server"
    subscription = PrivatePub.subscription(:timestamp => 123, :channel => "hello")
    subscription[:timestamp].should == 123
    subscription[:channel].should == "hello"
    subscription[:server].should == "server"
  end

  it "does a sha1 digest of channel, timestamp, and secret token" do
    PrivatePub.config[:secret_token] = "token"
    subscription = PrivatePub.subscription(:timestamp => 123, :channel => "channel")
    subscription[:signature].should == Digest::SHA1.hexdigest("tokenchannel123")
  end

  it "formats a message hash given a channel and a string for eval" do
    PrivatePub.config[:secret_token] = "token"
    PrivatePub.message("chan", "foo").should eq(
      :ext => {:private_pub_token => "token"},
      :channel => "chan",
      :data => {
        :channel => "chan",
        :eval => "foo"
      }
    )
  end

  it "formats a message hash given a channel and a hash" do
    PrivatePub.config[:secret_token] = "token"
    PrivatePub.message("chan", :foo => "bar").should eq(
      :ext => {:private_pub_token => "token"},
      :channel => "chan",
      :data => {
        :channel => "chan",
        :data => {:foo => "bar"}
      }
    )
  end

  it "publish message as json to server using Net::HTTP" do
    PrivatePub.config[:server] = "http://localhost"
    message = stub(:to_json => "message_json")
    Net::HTTP.should_receive(:post_form).with(URI.parse("http://localhost"), :message => "message_json").and_return(:result)
    PrivatePub.publish_message(message).should == :result
  end

  it "raises an exception if no server is specified when calling publish_message" do
    lambda {
      PrivatePub.publish_message("foo")
    }.should raise_error(PrivatePub::Error)
  end

  it "publish_to passes message to publish_message call" do
    PrivatePub.should_receive(:message).with("chan", "foo").and_return("message")
    PrivatePub.should_receive(:publish_message).with("message").and_return(:result)
    PrivatePub.publish_to("chan", "foo").should == :result
  end

  it "has a Faye rack app instance" do
    PrivatePub.faye_app.should be_kind_of(Faye::RackAdapter)
  end

  it "says signature has expired when time passed in is greater than expiration" do
    PrivatePub.config[:signature_expiration] = 30*60
    time = PrivatePub.subscription[:timestamp] - 31*60*1000
    PrivatePub.signature_expired?(time).should be_true
  end

  it "says signature has not expired when time passed in is less than expiration" do
    PrivatePub.config[:signature_expiration] = 30*60
    time = PrivatePub.subscription[:timestamp] - 29*60*1000
    PrivatePub.signature_expired?(time).should be_false
  end

  it "says signature has not expired when expiration is nil" do
    PrivatePub.config[:signature_expiration] = nil
    PrivatePub.signature_expired?(0).should be_false
  end
end
