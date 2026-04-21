class SecuritySkillExtractor
  SKILLS = {
    "Cryptography"       => [ "cryptograph", "encryption", "decryption" ],
    "Zero Trust"         => [ "zero trust", "zero-trust" ],
    "Penetration Testing" => [ "pentest", "penetration test" ],
    "Smart Contracts"    => [ "smart contract", "solidity" ],
    "Blockchain"         => [ "blockchain", "distributed ledger" ],
    "Bitcoin"            => [ "bitcoin", "lightning network" ],
    "Nostr"              => [ "nostr", "nip-07", "nip07" ],
    "WebAuthn/Passkeys"  => [ "webauthn", "passkey", "fido2" ],
    "OAuth/OIDC"         => [ "oauth", "oidc", "openid connect" ],
    "DevSecOps"          => [ "devsecops" ],
    "SAST/DAST"          => [ "sast", "dast", "static analysis", "dynamic analysis" ],
    "Supply Chain"       => [ "supply chain", "sbom", "dependency audit" ],
    "Vault/Secrets"      => [ "vault", "secrets management", "hashicorp vault" ],
    "IAM"                => [ "\\biam\\b", "identity.access management" ],
    "PKI"                => [ "\\bpki\\b", "certificate authority", "x\\.509" ],
    "ZK Proofs"          => [ "zero knowledge", "zk-proof", "zk proof", "zksnark" ],
    "Docker/K8s Security" => [ "container security", "pod security", "kubernetes security" ],
    "Compliance"         => [ "soc2", "soc 2", "iso 27001", "gdpr", "hipaa", "pci.dss", "compliance" ],
    "Threat Modeling"    => [ "threat model" ],
    "Python"             => [ "python" ],
    "Go"                 => [ "golang", "\\bgo\\b" ],
    "Rust"               => [ "\\brust\\b" ],
    "AWS Security"       => [ "aws security", "guardduty", "security hub", "aws iam" ],
    "Terraform"          => [ "terraform" ],
    "CI/CD Security"     => [ "ci/cd security", "pipeline security", "secure pipeline" ]
  }.freeze

  PATTERNS = SKILLS.transform_values do |variants|
    Regexp.new("\\b(?:#{variants.join('|')})\\b", Regexp::IGNORECASE)
  end.freeze

  def self.top_skills(jobs, limit: 10)
    rows = jobs.where.not(description: [ nil, "" ]).pluck(:title, :description)
    return [] if rows.empty?

    counts = Hash.new(0)
    rows.each do |title, description|
      blob = "#{title} #{description}"
      PATTERNS.each do |skill, pattern|
        counts[skill] += 1 if blob.match?(pattern)
      end
    end

    total = rows.length
    counts.sort_by { |_, c| -c }.first(limit).map do |name, count|
      [ name, count, (count.to_f / total * 100).round ]
    end
  end
end
