# frozen_string_literal: true

module Rbrun
  module Providers
    # Normalized resource types shared across all cloud providers.
    # Each provider's client transforms API responses into these structs.
    module Types
      # Compute instance / virtual machine.
      Server = Struct.new(
        :id,          # String - provider's unique identifier
        :name,        # String - server name
        :status,      # String - "running", "stopped", "starting", etc.
        :public_ipv4, # String|nil - public IP address
        :private_ipv4, # String|nil - private/internal IP
        :instance_type, # String - e.g. "cpx11", "DEV1-S"
        :image,       # String - OS image name
        :location,    # String - datacenter/zone (e.g. "ash-dc1", "fr-par-1")
        :labels,      # Hash - tags/labels
        :created_at,  # String - ISO8601 timestamp
        keyword_init: true
      )

      # SSH public key for server access.
      SshKey = Struct.new(
        :id,          # String - provider's unique identifier
        :name,        # String - key name
        :fingerprint, # String - key fingerprint
        :public_key,  # String - the public key content
        :created_at,  # String - ISO8601 timestamp
        keyword_init: true
      )

      # Firewall / Security Group.
      Firewall = Struct.new(
        :id,          # String - provider's unique identifier
        :name,        # String - firewall name
        :rules,       # Array - firewall rules (provider-specific format)
        :created_at,  # String - ISO8601 timestamp
        keyword_init: true
      )

      # Private network / VPC.
      Network = Struct.new(
        :id,          # String - provider's unique identifier
        :name,        # String - network name
        :ip_range,    # String|nil - CIDR range (e.g. "10.0.0.0/16")
        :subnets,     # Array - subnet definitions
        :location,    # String|nil - region/zone
        :created_at,  # String - ISO8601 timestamp
        keyword_init: true
      )

      # Block storage volume.
      Volume = Struct.new(
        :id,          # String - provider's unique identifier
        :name,        # String - volume name
        :size_gb,     # Integer - size in gigabytes
        :volume_type, # String - storage type (e.g. "b_ssd", "local")
        :status,      # String - "available", "attached", etc.
        :server_id,   # String|nil - attached server ID
        :location,    # String - datacenter/zone
        :device_path, # String|nil - linux device path (e.g. /dev/sdb)
        :created_at,  # String - ISO8601 timestamp
        keyword_init: true
      )
    end
  end
end
