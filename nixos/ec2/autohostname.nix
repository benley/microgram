{ config, lib, pkgs, ... }:
let
  inherit (lib) concatStringsSep mapAttrsToList mkOverride mkOption types optionalString;

  inherit (import <microgram/sdk.nix>) sdk pkgs;
  retry = "${sdk.retry}/bin/retry";
  base64 = "${pkgs.coreutils}/bin/base64";
  jq = "/usr/bin/env LD_LIBRARY_PATH=${pkgs.jq}/lib ${pkgs.jq}/bin/jq";
  curl = "${pkgs.curl}/bin/curl -s --retry 3 --retry-delay 0 --fail";
  curl-nofail = "${pkgs.curl}/bin/curl -s --retry 3 --retry-delay 0";
  wget = "${pkgs.wget}/bin/wget -q --retry-connrefused -O -";
  awk = "${pkgs.gawk}/bin/awk";
  openssl = "${pkgs.openssl}/bin/openssl";
  hostname = "${pkgs.nettools}/bin/hostname";
  ip = "${pkgs.iproute}/sbin/ip";
  bash = "${pkgs.bash}/bin/bash";
  xargs = "${pkgs.findutils}/bin/xargs";

  retry-wrapper = script: pkgs.writeScript "retry-${script.name}" ''
    ${retry} ${script}
  '';

  # TODO: move to a proper package
  register-hostname = {
    zoneId, zone, iamCredentialName,
    useLocalHostname,
    query ? if useLocalHostname then "local-ipv4" else "public-hostname",
    recordType ? if useLocalHostname then "A" else "CNAME"
  }: sdk.writeBashScriptOverride ["SC2046"] "ec2-register-hostname-${zone}" ''

    export SSL_CERT_FILE='${sdk.cacert}/etc/ssl/certs/ca-bundle.crt'

    date=$(${curl} -I https://route53.amazonaws.com/date | ${awk} '/^Date: / {sub("Date: ", "", $0); sub("\\r", "", $0); print $0}')

    iam="${iamCredentialName}"
    if [ -z "$iam" ]; then
      # autodetect
      set -- $(${curl} http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null | head -1)
      iam="$1"
      if [ -z "$iam" ]; then
        exit 1
      fi
    fi

    set -- $(${curl} http://169.254.169.254/latest/user-data | ${jq} -r .hostname || true)
    [ -n "$1" ] && HOSTNAME="$1"; HOSTNAME="$HOSTNAME.${zone}"

    set -- $(${wget} http://169.254.169.254/latest/meta-data/iam/security-credentials/${iamCredentialName} \
              | ${jq} -r '.SecretAccessKey, .AccessKeyId, .Token')

    signature="$(echo -n "$date" | ${openssl} dgst -binary -sha1 -hmac "$1" | ${base64})"
    auth_header="X-Amzn-Authorization: AWS3-HTTPS AWSAccessKeyId=$2,Algorithm=HmacSHA1,Signature=$signature"
    record_value=$(${wget} http://169.254.169.254/latest/meta-data/${query})

    ${curl-nofail} -d @/dev/stdin \
          -H "Content-Type: text/xml" \
          -H "x-amz-date: $date" \
          -H "$auth_header" \
          -H "x-amz-security-token: $3" \
          -X POST https://route53.amazonaws.com/2013-04-01/hostedzone/${zoneId}/rrset <<__EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
    <ChangeBatch>
       <Changes>
          <Change>
             <Action>UPSERT</Action>
             <ResourceRecordSet>
                <Name>$HOSTNAME</Name>
                <Type>${recordType}</Type>
                <TTL>30</TTL>
                <ResourceRecords>
                   <ResourceRecord><Value>$record_value</Value></ResourceRecord>
                </ResourceRecords>
             </ResourceRecordSet>
          </Change>
       </Changes>
    </ChangeBatch>
    </ChangeResourceRecordSetsRequest>
    __EOF

    curl_error=$?

    echo
    exit $curl_error
 '';

  ec2-autohostname = ''
    set -efuo pipefail
    ${ip} route delete blackhole 169.254.169.254 2>/dev/null || true
    # registering route 53 hostnames if any:
    echo ${concatStringsSep " " (
        mapAttrsToList (_: args: retry-wrapper (register-hostname {
         zone = args.name;
         inherit (args) zoneId iamCredentialName useLocalHostname;
       })) config.ec2.route53RegisterHostname)} | ${xargs} -n1 -P2 ${bash}
  '';
in
{
  options = {
    ec2.route53RegisterHostname = mkOption {
      type = types.attrsOf (types.submodule ({ lib, name, ... }: with lib; {
        options = {
          name = mkOption {
            type = types.string;
            default = name;
            description = ''
              Route53 Hosted Domain Name (can be a sub-domain of a more high-level domain name).
            '';
          };

          zoneId = mkOption {
            type = types.string;
            example = "ZOZONEZONEZONE";
            description = ''
              Route53 Hosted Zone ID for the domain specified in name;
            '';
          };

          iamCredentialName = mkOption {
            type = types.string;
            example = "doge-iam-dns-profile";
            default = "";
            description = ''
              Instance IAM Role name. Leave empty to autodetect.
            '';
          };

          useLocalHostname = mkOption {
            type = types.bool;
            default = false;
            description = ''
              CNAMEs to the internal hostname. Useful when doing VPC tunneling.
            '';
          };
        };
      }));

      default = {};
    };
  };

  config = {
    systemd.services.ec2-autohostname = {
      description = "EC2: periodically apply dynamic hostname";

      wantedBy = [ "multi-user.target" ];
      after = [ "fetch-ec2-data.service" ];

      script = ''
        while true; do
          ${sdk.writeBashScript "ec2-autohostname" ec2-autohostname}
          sleep $((120 + $RANDOM % 40))m
        done
      '';

      serviceConfig.Restart = "always";
      unitConfig.X-StopOnReconfiguration = true;
    };
  };
}
