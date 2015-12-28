FROM ubuntu:14.04.3
MAINTAINER Nicola <niquola@gmail.com>, \
           BazZy <bazzy.bazzy@gmail.com>, \
           Danil Kutkevich <danil@kutkevich.org>

ENV REFRESHED_AT 2015-12-24

RUN localedef --force --inputfile=en_US --charmap=UTF-8 \
    --alias-file=/usr/share/locale/locale.alias \
    en_US.UTF-8
ENV LANG en_US.UTF-8

RUN apt-get -y update
RUN apt-get -y upgrade

RUN apt-get install -y curl
RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main' \
    > /etc/apt/sources.list.d/pgdg.list
RUN curl --silent https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
    sudo apt-key add -

RUN apt-get -y update
RUN apt-get -y upgrade

ENV PG_MAJOR 9.4

RUN apt-get install -y postgresql-$PG_MAJOR

# In case of plv8 compilation issues address to README in
# <https://github.com/clkao/docker-postgres-plv8>.

RUN apt-get install -y git build-essential libv8-dev postgresql-server-dev-$PG_MAJOR
RUN apt-get install -y nodejs-dev

ENV PLV8_BRANCH r1.4

RUN cd /tmp && git clone -b $PLV8_BRANCH https://github.com/plv8/plv8.git \
    && cd /tmp/plv8 \
    && make all install

# Adjust PostgreSQL configuration so that remote connections to the
# database are possible.
RUN echo 'host all  all    0.0.0.0/0  md5' >> /etc/postgresql/$PG_MAJOR/main/pg_hba.conf
RUN echo 'local all  all    trust' >> /etc/postgresql/$PG_MAJOR/main/pg_hba.conf
RUN echo "listen_addresses='*'" >> /etc/postgresql/$PG_MAJOR/main/postgresql.conf

USER postgres

# Fix PostgreSQL locale
# <http://stackoverflow.com/questions/16736891/pgerror-error-new-encoding-utf8-is-incompatible#16737776>,
# <http://www.postgresql.org/message-id/43FE1E65.3030000@genome.chop.edu>,
# <http://www.postgresql.org/docs/current/static/multibyte.html#AEN35730>.
RUN service postgresql start \
    && psql --command="UPDATE pg_database SET datistemplate = FALSE WHERE datname = 'template1';" \
    && psql --command="DROP DATABASE template1;" \
    && psql --command="CREATE DATABASE template1 WITH TEMPLATE = template0 ENCODING = 'UNICODE' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8';" \
    && psql --command="UPDATE pg_database SET datistemplate = TRUE WHERE datname = 'template1';" \
    && psql --command="CREATE ROLE fhirbase WITH SUPERUSER LOGIN PASSWORD 'fhirbase';" \
    && psql --command="CREATE DATABASE fhirbase WITH OWNER fhirbase ENCODING = 'UTF8';"

USER root

RUN useradd --user-group --create-home --shell /bin/bash fhirbase \
    && echo 'fhirbase:fhirbase' | chpasswd && adduser fhirbase sudo
RUN echo 'fhirbase ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

USER fhirbase

RUN cd ~ \
    && git clone https://github.com/fhirbase/fhirbase-plv8.git fhirbase \
    && cd ~/fhirbase \
    && git submodule update --init --recursive

# Install nodejs.
RUN curl --silent -o- https://raw.githubusercontent.com/creationix/nvm/v0.29.0/install.sh \
    | bash
RUN bash -lc 'source ~/.nvm/nvm.sh && nvm install 5.3'
RUN bash -lc 'cd ~/fhirbase && source ~/.nvm/nvm.sh && nvm use 5.3 \
              && npm install'
RUN bash -lc 'cd ~/fhirbase/plpl && source ~/.nvm/nvm.sh && nvm use 5.3 \
              && npm install'

# Install fhirbase.
RUN bash -lc 'sudo service postgresql start \
              && cd ~/fhirbase \
              && source ~/.nvm/nvm.sh && nvm use 5.3 \
              && export PATH="$HOME"/fhirbase/node_modules/coffee-script/bin:"$PATH" \
              && export DATABASE_URL=postgres://fhirbase:fhirbase@localhost:5432/fhirbase \
              && ~/fhirbase/build.sh \
              && cat ~/fhirbase/tmp/build.sql | psql fhirbase'

# Run test suite.
RUN bash -lc 'sudo service postgresql start \
              && cd ~/fhirbase \
              && source ~/.nvm/nvm.sh && nvm use 5.3 \
              && export DATABASE_URL=postgres://fhirbase:fhirbase@localhost:5432/fhirbase \
              && npm run test'

# Expose the PostgreSQL port.
EXPOSE 5432

# Add VOLUMEs to allow backup of config, logs, socket and databases
VOLUME  ['/etc/postgresql', '/var/log/postgresql', '/var/lib/postgresql', '/var/run/postgresql']

WORKDIR ~/fhirbase

CMD sudo service postgresql start
