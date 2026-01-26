VERSION ?= 0.1.17
DOCKERHUB_USER ?= plan9better
LOCAL_REGISTRY ?= 192.168.10.201:5000

.PHONY: publish test all vxlandlord xfrminion restctl charon operator

publish:
	docker build -t $(DOCKERHUB_USER)/vxlandlord:$(VERSION) --platform linux/amd64 --file ./vxlandlord.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/vxlandlord:$(VERSION) 

	docker build -t $(DOCKERHUB_USER)/xfrminion:$(VERSION) --platform linux/amd64 --file ./xfrminion.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/xfrminion:$(VERSION) 

	docker build -t $(DOCKERHUB_USER)/restctl:$(VERSION) --platform linux/amd64 --file ./restctl.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/restctl:$(VERSION)

	docker build -t $(DOCKERHUB_USER)/operator:$(VERSION) --platform linux/amd64 --file ./operator.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/operator:$(VERSION) 

	docker build -t $(DOCKERHUB_USER)/charon:$(VERSION) --platform linux/amd64 --file ./charon.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/charon:$(VERSION) 

	docker build -t $(DOCKERHUB_USER)/xfrminjector:$(VERSION) --platform linux/amd64 --file ./xfrminjector.Dockerfile --build-arg PLATFORM=amd64 .
	docker push $(DOCKERHUB_USER)/xfrminjector:$(VERSION) 

test:
	docker build -t $(DOCKERHUB_USER)/vxlandlord:latest-dev-test --platform linux/arm64 --file ./vxlandlord.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/vxlandlord:latest-dev-test 

	docker build -t $(DOCKERHUB_USER)/xfrminion:latest-dev-test --platform linux/arm64 --file ./xfrminion.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/xfrminion:latest-dev-test 

	docker build -t $(DOCKERHUB_USER)/restctl:latest-dev-test --platform linux/arm64 --file ./restctl.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/restctl:latest-dev-test

	docker build -t $(DOCKERHUB_USER)/operator:latest-dev-test --platform linux/arm64 --file ./operator.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/operator:latest-dev-test 

	docker build -t $(DOCKERHUB_USER)/charon:latest-dev-test --platform linux/arm64 --file ./charon.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/charon:latest-dev-test 

	docker build -t $(DOCKERHUB_USER)/xfrminjector:latest-dev-test --platform linux/arm64 --file ./xfrminjector.Dockerfile --build-arg PLATFORM=arm64 .
	docker push $(DOCKERHUB_USER)/xfrminjector:latest-dev-test 

all:
	GOFLAGS="-trimpath -buildvcs=false" KO_DOCKER_REPO="192.168.10.201:5000" ko resolve --push=true -B -f helm-values-template.yaml > helm/values.yaml
