#!ruby

require 'multi_json'
require 'ringcentral_sdk'

class RingCentralSdkBootstrap

  def load_credentials(credentials_filepath, usage_string=nil)
    unless credentials_filepath.to_s.length>0
      raise usage_string.to_s
    end

    unless File.exists?(credentials_filepath.to_s)
      raise "Error: credentials file does not exist for: #{credentials_filepath}"
    end

    @credentials = MultiJson.decode(IO.read(credentials_filepath), :symbolize_keys=>true)
  end

  def get_sdk_with_token(env=:sandbox, app_index=0, resource_owner_index=0)
    credentials = @credentials

    rcsdk = RingCentralSdk.new(
      credentials[env][:applications][app_index][:app_key],
      credentials[env][:applications][app_index][:app_secret],
      credentials[env][:api][:server]
    )

    rcsdk.authorize(
      credentials[env][:resource_owners][resource_owner_index][:username],
      credentials[env][:resource_owners][resource_owner_index][:extension],
      credentials[env][:resource_owners][resource_owner_index][:password],
    ) 

    return rcsdk
  end

end

boot = RingCentralSdkBootstrap.new
boot.load_credentials(ARGV.shift, 'Usage: subscription.rb path/to/credentials.json [extensionId]')
rcsdk = boot.get_sdk_with_token()

extension_id = ARGV.shift.to_s
extension_id = '~' unless extension_id.length>0

# An example observer object
class MyObserver
  def update(message)
    puts "Subscription Message Received"
    puts JSON.dump(message)
  end
end

def run_subscription(rcsdk, extension_id='~')
  # Create an observable subscription and add your observer
  sub = rcsdk.create_subscription()
  sub.subscribe(["/restapi/v1.0/account/~/extension/#{extension_id}/presence"])

  sub.add_observer(MyObserver.new())

  puts "Click any key to finish"

  stop_script = gets

  # End the subscription
  sub.destroy()
end

run_subscription(rcsdk, extension_id)

puts "DONE"