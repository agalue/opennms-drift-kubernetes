# Nephron

As there are no bundled JARs released for Nephron, this will build a Flink image with a given version of Nephron compiled in the `/data` directory.

To build the image for version `v0.3.0` (which should be a valid `tag` of the Nephron GitHub repository), do the following:

```bash
docker build -t agalue/nephron:0.3.0 --build-arg NEPHRON_VERSION=v0.3.0 .
docker push agalue/nephron:0.3.0
```

> **NOTE:** If you plan to use a different identifier, make sure to update the YAML manifest for Kubernetes. 
