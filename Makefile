VERSION ?= 0.1.19-abl2
DOCKERHUB_USER ?= ablmnzde
IMAGE_PREFIX ?= ipman-
LOCAL_REGISTRY ?= $(DOCKERHUB_USER)/$(IMAGE_PREFIX)

.PHONY: publish test all vxlandlord xfrminion restctl charon operator

publish:
	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)vxlandlord:$(VERSION) --platform linux/amd64 --file ./vxlandlord.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)vxlandlord:$(VERSION)

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)xfrminion:$(VERSION) --platform linux/amd64 --file ./xfrminion.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)xfrminion:$(VERSION)

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)restctl:$(VERSION) --platform linux/amd64 --file ./restctl.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)restctl:$(VERSION)

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)operator:$(VERSION) --platform linux/amd64 --file ./operator.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)operator:$(VERSION)

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)charon:$(VERSION) --platform linux/amd64 --file ./charon.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)charon:$(VERSION)

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)xfrminjector:$(VERSION) --platform linux/amd64 --file ./xfrminjector.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)xfrminjector:$(VERSION)

test:
	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)vxlandlord:latest-dev-test --platform linux/arm64 --file ./vxlandlord.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)vxlandlord:latest-dev-test

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)xfrminion:latest-dev-test --platform linux/arm64 --file ./xfrminion.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)xfrminion:latest-dev-test

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)restctl:latest-dev-test --platform linux/arm64 --file ./restctl.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)restctl:latest-dev-test

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)operator:latest-dev-test --platform linux/arm64 --file ./operator.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)operator:latest-dev-test

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)charon:latest-dev-test --platform linux/arm64 --file ./charon.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)charon:latest-dev-test

	docker build -t $(DOCKERHUB_USER)/$(IMAGE_PREFIX)xfrminjector:latest-dev-test --platform linux/arm64 --file ./xfrminjector.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/$(IMAGE_PREFIX)xfrminjector:latest-dev-test

all:
	GOFLAGS="-trimpath -buildvcs=false" KO_DOCKER_REPO="$(LOCAL_REGISTRY)" ko resolve --push=true -B -f helm-values-template.yaml > helm/values.yaml
