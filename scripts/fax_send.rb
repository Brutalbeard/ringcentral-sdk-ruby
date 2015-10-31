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

to_phone_number = ARGV.shift

unless to_phone_number.to_s.length>0
  abort("Usage: fax_send.rb rc-credentials.json phone_number my_file.pdf")
end

file_name = ARGV.shift

unless file_name.to_s.length>0
  abort("Usage: fax_send.rb rc-credentials.json phone_number my_file.pdf")
end

unless File.exists?(file_name.to_s)
  abort("Error: file to fax does not exist for: #{file_name}")
end

def send_fax(rcsdk, to_phone_number, file_name)
  fax = RingCentralSdk::Helpers::CreateFaxRequest.new(
    nil,
    {
    	:to            => [{:phoneNumber => to_phone_number}],
    	:faxResolution => 'High',
    	:coverPageText => 'RingCentral Fax Base64 using Ruby!'
    },
    :file_name       => file_name,
    :base64_encode   => true
  )

  puts fax.body

  client = rcsdk.client

  if 1==1
    response = client.post do |req|
      req.url fax.url
      req.headers['Content-Type'] = fax.content_type
      req.body = fax.body
    end
    puts response.body.to_s
  end

end

send_fax(rcsdk, to_phone_number, file_name)

puts "DONE"