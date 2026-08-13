# Infrastructure, containers, and the pipeline

Application code gets reviewed. The YAML next to it usually does not, and it is
where the blast radius lives: a wrong line in a handler leaks one record, a
wrong line in an IAM policy leaks the bucket.

Treat every file here as code — reviewed, in version control, and covered by the
same "no secret in the repository" rule as everything else.

## Containers

- **Do not run as root.** A `USER` line that is not there means root, and root in
  the container is one escape away from root on the host.
- **Pin the base image** by digest, or at minimum by a specific tag. `:latest`
  means the image you tested and the image you shipped are different artefacts.
- **Secrets never enter the image.** Not `ENV`, not `ARG`, not a file deleted in
  a later layer — every layer is readable in the final image. Use build secrets
  or inject at runtime.
- `COPY`, not `ADD`. `ADD` unpacks archives and fetches URLs, which is a remote
  code path nobody asked for.
- `COPY . .` ships `.git`, `.env`, and every local credential. Use a
  `.dockerignore` and check what actually landed.
- Smaller base, smaller surface. A distroless or slim image cannot be exploited
  through a shell it does not contain.
- Health checks and resource limits are security controls too: a container with
  no memory limit is how one tenant takes down the node.

## Terraform, Pulumi, CloudFormation

- **Public by accident** is the classic: a storage bucket, a database, a
  snapshot, a queue. Check the ACL and the policy, not just the resource.
- **`0.0.0.0/0`** on anything that is not port 443 on a load balancer needs a
  written reason. SSH and database ports especially.
- **IAM is where least privilege actually happens.** `Action: "*"` or
  `Resource: "*"` in a policy you wrote today becomes the policy everything
  copies from next quarter.
- **State files contain secrets** in plaintext — database passwords, generated
  keys. Remote backend, encrypted, access-controlled. Never in the repository.
- Encryption at rest and logging are one line each and are always cheaper to add
  before launch than after an incident.
- Deletion protection and backups on anything stateful. `terraform destroy` on
  the wrong workspace is a routine human error, not an exotic one.

## Kubernetes

- No `privileged: true`, no `hostNetwork`, no `hostPath` mount, unless the reason
  is written down next to it.
- Set `runAsNonRoot`, drop capabilities, and set `readOnlyRootFilesystem` where
  the workload allows it.
- Secrets as mounted files rather than environment variables — environment
  variables leak into crash dumps, `/proc`, and child processes.
- Resource requests and limits on everything. A NetworkPolicy, or the default is
  that every pod can reach every other pod.

## The pipeline is production

CI holds credentials for everything it deploys to, which makes it a higher-value
target than most of what it deploys.

- **Pin third-party actions to a commit SHA**, not a tag. A tag can be moved.
- **`pull_request_target` runs with secrets and checks out the fork's code.**
  Combining the two is remote code execution against your CI. If you must use
  it, do not check out the PR head.
- Grant the smallest `permissions:` block that works. The default token is often
  write-scoped to the whole repository.
- Never `echo` a secret to debug a job. The log outlives the job, and on a public
  repository it outlives the mistake.
- A workflow triggered by a fork must not see production secrets. Use an
  environment with required reviewers for anything that deploys.

## Scanning

Optional and opt-in, because they need a tool and produce noise on a codebase
that has never run them:

| Target | Tool |
|---|---|
| Container image | `trivy image <ref>` |
| Terraform / K8s manifests | `checkov -d .` or `trivy config .` |
| Filesystem, any of the above | `trivy fs .` |

Same rule as every other gate: not installed is **absent**, never a pass. And a
finding suppressed to make the pipeline green is a finding you will meet again
under worse conditions.
