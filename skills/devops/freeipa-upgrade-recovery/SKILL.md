---
name: freeipa-upgrade-recovery
description: Use when diagnosing or recovering FreeIPA/IdM servers after upgrades, especially ipactl master-service discovery failures, CA LDAP profile migration errors, replica suffix inconsistencies, and certmonger HTTP certificate SAN/stuck-request issues.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [freeipa, idm, 389-ds, certmonger, dogtag, devops, recovery]
    related_skills: [linux-infrastructure-operations]
---

# FreeIPA Upgrade Recovery

## Overview

Use this skill for FreeIPA/Red Hat IdM servers that become unreachable, fail `ipa-server-upgrade`, or cannot be started cleanly after a normal package or OS upgrade.

It captures the recovery pattern from a Rocky/RHEL 9.7 FreeIPA case where three separate issues were fixed:

1. CA LDAP profile migration failed with `EmptyResult` under `o=ipaca`.
2. `ipactl` printed a misleading master mismatch because local LDAP subtree searches did not return the host's master service entries.
3. The HTTP certmonger request was stuck and missing the `ipa-ca.<domain>` DNS SAN because a pinfile was tracked for a key that did not need a PIN.

The key principle: **prove whether data is missing globally or only invisible/broken on the local replica before editing LDAP manually.** Prefer native FreeIPA replication repair (`ipa-replica-manage`, `ipa-csreplica-manage`, `getcert`) over manual LDIF patches.

## When to Use

Use when FreeIPA/IdM shows any of these symptoms after upgrade or restore:

- `ipa-server-upgrade` fails in Dogtag/CA profile migration.
- `ipactl start` says the configured hostname does not match any master, but the host is listed in LDAP.
- Master service entries appear present by exact DN lookup but are missing from subtree searches.
- Healthcheck reports invalid IPA master roles, PKINIT role problems, or certificate SAN mismatches.
- certmonger request status is `NEED_KEYINFO_READ_PIN`, `NEWLY_ADDED_NEED_KEYINFO_READ_PIN`, or `stuck: yes`.
- HTTP certificate lacks `ipa-ca.<domain>` while that DNS alias points to this CA master.

Do not use for:

- Fresh FreeIPA installations.
- Client enrollment failures unrelated to server replica state.
- Kerberos-only client problems where `ipactl status` and `ipa-healthcheck` are clean.

## Safety Rules

1. **Back up before destructive repair.** Before reindex/reinitialize/manual edits, save relevant logs/config and prefer native exports/backups.
2. **Do not manually add LDAP service entries if exact DN lookup already works.** If exact lookup works but subtree search fails, manual `ldapadd` will hit `Already exists` or mask the real issue.
3. **For CA masters, repair both suffixes when CA data is involved.** Domain data lives under `dc=...`; Dogtag/CA data lives under `o=ipaca`.
4. **Use a known healthy supplier.** Compare local results with another master before reinitialization.
5. **Stop before destructive steps if backups/exports fail.** Do not reindex, reinitialize, or wipe state after failed backup/export unless the user explicitly accepts the risk.

## Issue Pattern 1: CA LDAP Profile Migration `EmptyResult`

### Symptom

`ipa-server-upgrade` aborts around CA profile migration:

```text
[Ensuring CA is using LDAPProfileSubsystem]
[Migrating certificate profiles to LDAP]
ERROR IPA server upgrade failed
...
cainstance.migrate_profiles_to_ldap()
...
_get_ldap_profile_states()
...
EmptyResult: no matching entry found
```

The failing search is typically under:

```text
ou=certificateProfiles,ou=ca,o=ipaca
```

with filter:

```text
(objectClass=certProfile)
```

### Interpretation

This points at CA/Dogtag LDAP state, not necessarily Tomcat REST reachability. Check whether Tomcat actually failed or whether profile lookup returned empty.

### Fix Pattern

If a healthy CA peer has the expected CA profile data, reinitialize the CA suffix from that peer:

```bash
ipa-csreplica-manage re-initialize --from=<healthy-ca-peer-fqdn>
```

If domain suffix data is also inconsistent, reinitialize both:

```bash
ipa-replica-manage re-initialize --from=<healthy-peer-fqdn>
ipa-csreplica-manage re-initialize --from=<healthy-ca-peer-fqdn>
```

## Issue Pattern 2: `ipactl` Master Mismatch / Service Metadata Not Found

### Symptom

`ipactl start` fails with a misleading message:

```text
Failed to read data from service file: Failed to get list of services to probe status!
Configured hostname '<host>' does not match any master server in LDAP:
<host>
<other-masters>
Shutting down
```

If the current host is listed, the message is misleading. `ipactl` may have failed to find service child entries under the host's master container.

### Diagnostic Query

Start only Directory Server if needed:

```bash
systemctl start dirsrv@<INSTANCE>.service
```

Use LDAPI/EXTERNAL bind so Kerberos does not need to work yet:

```bash
ldapsearch -Y EXTERNAL -H ldapi://%2fvar%2frun%2fslapd-<INSTANCE>.socket -Q -LLL \
  -b 'cn=<host>,cn=masters,cn=ipa,cn=etc,<base-dn>' \
  -s sub \
  '(&(objectClass=ipaConfigObject)(|(ipaConfigString=enabledService)(ipaConfigString=hiddenService)))' \
  dn cn ipaConfigString
```

Expected service entries usually include some or all of:

```text
KDC
KPASSWD
HTTP
OTPD
KEYS
CA
DNS
KRA
```

### Exact DN vs Subtree Test

If subtree search returns no entries, test exact DNs such as:

```text
cn=KDC,cn=<host>,cn=masters,cn=ipa,cn=etc,<base-dn>
cn=HTTP,cn=<host>,cn=masters,cn=ipa,cn=etc,<base-dn>
cn=CA,cn=<host>,cn=masters,cn=ipa,cn=etc,<base-dn>
```

If exact DN lookup works but subtree search from the parent returns no child entries, the problem is likely local 389-DS database/search/replica state, not missing FreeIPA metadata.

### Compare with Healthy Peer

Run the same logical query against or from a healthy peer. If the peer can see the affected host's service entries, do not manually patch LDAP; reinitialize the local replica from the healthy supplier.

### Fix Pattern

For domain suffix repair:

```bash
ipa-replica-manage re-initialize --from=<healthy-peer-fqdn>
```

For CA masters, also repair CA suffix:

```bash
ipa-csreplica-manage re-initialize --from=<healthy-ca-peer-fqdn>
```

Then clear stale `ipactl` cache and restart:

```bash
rm -f /run/ipa/services.list /var/run/ipa/services.list
ipactl restart
ipactl status
```

Expected final state:

```text
Directory Service: RUNNING
krb5kdc Service: RUNNING
kadmin Service: RUNNING
httpd Service: RUNNING
ipa-custodia Service: RUNNING
pki-tomcatd Service: RUNNING
ipa-otpd Service: RUNNING
ipa: INFO: The ipactl command was successful
```

## Issue Pattern 3: HTTP Certmonger Request Stuck and Missing `ipa-ca` SAN

### Symptom

Healthcheck reports:

```text
IPACertDNSSAN: Certificate request id <id> with profile caIPAserviceCert for CA IPA does not have a DNS SAN ... matching name ipa-ca.<domain>
CertmongerStuckCheck: certmonger request <id> is in the stuck state
```

The request shows:

```text
status: NEED_KEYINFO_READ_PIN
stuck: yes
key pair storage: type=FILE,location='/var/lib/ipa/private/httpd.key',pinfile='...'
certificate: type=FILE,location='/var/lib/ipa/certs/httpd.crt'
CA: IPA
principal name: HTTP/<host>@<REALM>
profile: caIPAserviceCert
```

Repeated resubmission with `-D ipa-ca.<domain>` does not change the cert.

### Decisive Journal Evidence

Check certmonger logs:

```bash
journalctl -u certmonger --since '<time>' --no-pager | \
  grep -E '<request-id>|httpd.key|READ_PIN|PIN|stuck|error|Error' -C5
```

If the journal says:

```text
PIN was not needed to read private key '/var/lib/ipa/private/httpd.key', though one was provided. Treating this as an error.
```

then the key is not encrypted but certmonger is tracking a pinfile. That inconsistency causes the stuck state before useful CA submission.

### Fix Pattern

Back up request state:

```bash
REQ=<old-request-id>
CERT=/var/lib/ipa/certs/httpd.crt
KEY=/var/lib/ipa/private/httpd.key
PINFILE=/var/lib/ipa/passwds/<host>-443-RSA
OUT=/root/httpd-cert-repair-$(date +%F-%H%M%S)
mkdir -p "$OUT"

getcert list -i "$REQ" > "$OUT/getcert-request.before.txt"
cp -a "$CERT" "$KEY" "$PINFILE" "$OUT"/ 2>/dev/null || true
cp -a /var/lib/certmonger/requests/"$REQ" "$OUT"/certmonger-request-file.before 2>/dev/null || true
```

Stop tracking the broken request:

```bash
ipa-getcert stop-tracking -i "$REQ"
```

Recreate tracking **without** `-p` / without a pinfile:

```bash
ipa-getcert start-tracking \
  -f "$CERT" \
  -k "$KEY" \
  -T caIPAserviceCert \
  -K HTTP/<host>@<REALM> \
  -D <host> \
  -D ipa-ca.<domain> \
  -C /usr/libexec/ipa/certmonger/restart_httpd
```

Get the new request ID and resubmit:

```bash
NEWREQ=$(getcert list -f "$CERT" | awk -F"'" '/Request ID/ {print $2; exit}')

getcert resubmit -i "$NEWREQ" \
  -D <host> \
  -D ipa-ca.<domain> \
  -w
```

### Verification

```bash
getcert list -i "$NEWREQ"
openssl x509 -in /var/lib/ipa/certs/httpd.crt -noout -ext subjectAltName
ipa-healthcheck --source ipahealthcheck.ipa.certs --failures-only
```

Expected:

```text
status: MONITORING
stuck: no
dns: <host>,ipa-ca.<domain>
```

Certificate SAN should include both:

```text
DNS:<host>
DNS:ipa-ca.<domain>
```

Healthcheck should return:

```text
[]
```

## Final Global Verification

After recovery, check all certmonger requests:

```bash
getcert list | egrep 'Request ID|status:|stuck:|certificate:|CA:|expires:|dns:|principal name:'
```

Every request should be:

```text
status: MONITORING
stuck: no
```

Then run:

```bash
ipa-healthcheck --failures-only
# or local wrapper, if available
ipa-health-check.sh
```

Expected wrapper result:

```text
ERROR=0
WARNING=0
```

## Common Pitfalls

1. **Trusting the `ipactl` master mismatch literally.** If the host appears in the listed masters, inspect service child discovery before assuming the master entry is absent.

2. **Adding LDIF entries that already exist.** Exact DN lookup can work while subtree search fails. In that case manual LDAP additions are wrong.

3. **Reinitializing only `dc=...` on a CA master.** CA profile/cert data lives under `o=ipaca`; use `ipa-csreplica-manage` when CA suffix state is involved.

4. **Providing a pinfile for an unencrypted HTTP key.** certmonger can treat this as an error and stay in `NEED_KEYINFO_READ_PIN`.

5. **Assuming `getcert resubmit -D ...` fixes a stuck request.** If certmonger is stuck before keyinfo/CSR handling, fix the tracking state first.

6. **Leaving stale `/run/ipa/services.list`.** After service metadata repair, remove stale empty service-cache files before using `ipactl` again.

## Verification Checklist

- [ ] Directory Server starts or is reachable through LDAPI for diagnostics.
- [ ] Affected host's master service entries are visible via subtree search locally.
- [ ] Healthy supplier comparison completed before reinitialization.
- [ ] CA master repairs include both `ipa-replica-manage` and `ipa-csreplica-manage` when needed.
- [ ] `ipactl status` reports all expected services running.
- [ ] certmonger HTTP request is `MONITORING` and `stuck: no`.
- [ ] HTTP certificate SAN includes both host FQDN and `ipa-ca.<domain>` when the alias points to this CA master.
- [ ] `ipa-healthcheck --failures-only` is empty or only contains unrelated known warnings.
