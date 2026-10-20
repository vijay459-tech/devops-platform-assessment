# docker evidence: NOT RUN in the authoring environment

No docker (or network) was available when this repository was authored, so no output is claimed here.
Run these and paste the real output below, replacing this notice:

```
docker build -t service:local .
docker run -d --name svc -p 8080:8080 service:local
curl -fsS localhost:8080/health; curl -fsS localhost:8080/ready; curl -fsS localhost:8080/version
docker inspect --format "{{.Config.User}}" service:local   # expect 65532:65532
docker stop svc && docker inspect --format "{{.State.ExitCode}}" svc   # expect 0
```

## Output

_(paste here)_
