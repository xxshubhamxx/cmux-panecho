import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

req = urllib.request.Request("https://api.github.com/repos/xxshubhamxx/cmux-panecho/actions/runs/25229687334/jobs", headers={"Accept": "application/vnd.github.v3+json"})
resp = urllib.request.urlopen(req, context=ctx)
jobs = json.loads(resp.read().decode())
for job in jobs['jobs']:
    if job['conclusion'] == 'failure':
        print(f"FAILED JOB: {job['name']}")
        req2 = urllib.request.Request(f"https://api.github.com/repos/xxshubhamxx/cmux-panecho/actions/jobs/{job['id']}/logs", headers={"Accept": "text/plain"})
        log_resp = urllib.request.urlopen(req2, context=ctx)
        log = log_resp.read().decode()
        
        with open("/tmp/ci_failure.log", "w") as f:
            f.write(log)
