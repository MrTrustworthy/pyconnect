VERSION := 0.0.2
GROUP := None
SHELL = /bin/bash

install-hooks:
	pip3 install --user -r flake8-requirements.txt && \
	pip3 install --user gitpython==2.1.10 && \
	ln -sf ../../commithooks/pre-commit .git/hooks/pre-commit && \
	ln -sf ../../commithooks/prepare-commit-msg .git/hooks/prepare-commit-msg && \
	chmod +x .git/hooks/pre-commit && \
	chmod +x .git/hooks/prepare-commit-msg && \
	git config --bool flake8.strict true

install-system-packages:
	sudo apt-get install docker docker-compose kafkacat python-virtualenv python3.7 -y

install-virtualenv:
	[[ -d .venv ]] || virtualenv --python=3.7 ./.venv
	./.venv/bin/python -m pip install -r requirements.txt

install-hosts:
	[[ -n "`cat /etc/hosts | grep __start_pyconnect__`" ]] || \
	(cat ./hosts.template | sudo tee -a /etc/hosts)

uninstall-hosts:
	sudo sed -i /__start_pyconnect__/,/__stop_pyconnect__/d /etc/hosts


install-dev-env: install-system-packages install-virtualenv install-hosts install-hooks

reset-cluster:
	sudo docker-compose -f test/testenv-docker-compose.yml rm -f

boot-cluster: reset-cluster
	@( \
	  (curl -s "http://rest-proxy:8082/topics" >/dev/null) && \
	  (echo "Cluster already running.") \
	) \
	  || \
	( \
	  (echo "Starting Cluster") && \
	  (sudo docker-compose -f test/testenv-docker-compose.yml up --force-recreate -d) && \
	  (until (curl -s "http://rest-proxy:8082/topics" >/dev/null); do sleep 0.1s; done) \
	)

shutdown-cluster:
	@( \
	  (echo "Stopping Cluster") && \
	  (sudo docker-compose -f test/testenv-docker-compose.yml down) \
	)

run-full-tests: boot-cluster
	.venv/bin/python -m pytest --run-e2e --doctest-modules

run-tests:
	.venv/bin/python -m pytest --doctest-modules

consume-%: boot-cluster
	kafkacat -b broker:9092 -t $*

list-topics: boot-cluster
	kafkacat -b broker:9092 -L

check-offsets: boot-cluster
	test/kafka/bin/kafka-consumer-groups.sh --bootstrap-server broker:9092 --describe --group $(GROUP) --offsets --verbose
	test/kafka/bin/kafka-consumer-groups.sh --bootstrap-server broker:9092 --describe --group $(GROUP) --state --verbose
	test/kafka/bin/kafka-consumer-groups.sh --bootstrap-server broker:9092 --describe --group $(GROUP) --members --verbose

publish-test:
	python setup.py sdist
	twine upload dist/* -r testpypi

publish: publish-test
	twine upload dist/*
