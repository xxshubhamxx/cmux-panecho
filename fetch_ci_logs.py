import json
import urllib.request
import ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
r = urllib.request.urlopen("https://api.github.com/repos/xxshubhamxx/cmux-panecho/actions/runs/25229687334/jobs", context=ctx)
jobs = json.loads(r.read())['jobs']
for j in jobs:
    if j['conclusion'] == 'failure':
        r2 = urllib.request.urlopen(f"https://api.github.com/repos/xxshubhamxx/cmux-panecho/actions/jobs/{j['id']}/logs", context=ctx)
        log = r2.read().decode('utf-8')
        with open("/Users/shubhamgarg/Desktop/cmux_clone/cmux-panecho/ci_failure.log", "w") as f:
            f.write(log)
