# The hosted MCP endpoint, as a client.
#
# A service of its own rather than a route on the application: `lib/mcp` carries no
# `package.yml`, the application image does not contain it, and the SDK (with `json_schemer` and a
# schema compiler behind it) has no business in the container that answers the internet. The
# boundary is asserted by `test/components/package_boundaries_test.rb` and by the component's own
# `mcp_boundary_test.rb`.
#
# Pinned by digest, to the same bytes as the other Ruby stages here. Every message the repository's
# rules were written against was captured on Ruby 3.3.12, and a tag that moves is a second
# interpreter nobody verified.
ARG RUBY_IMAGE=ruby:3.3-slim@sha256:379ffc9ca20cae2655cb80cac53ee23e1e7d859c03a4cceb7f567d6ce4873cee
FROM ${RUBY_IMAGE}

WORKDIR /app

# The production image installs without the test group, for the same reason the application's
# image does: a test framework in the container that answers the internet is a toolchain in
# production. The argument exists so `scripts/dev.sh mcp` can build *this* image as its fallback
# and still run the suite in it — a fallback that could not load minitest would be a suite that
# never ran.
ARG BUNDLE_WITHOUT="development test"
ENV BUNDLE_WITHOUT=${BUNDLE_WITHOUT}

# `puma` compiles a native extension, and the slim base has no compiler. The toolchain is removed
# in the same layer, so the final image carries the built gem and not the tools that built it.
COPY Gemfile Gemfile.lock ./
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && bundle config set --local path /usr/local/bundle \
    && bundle install --jobs 4 --retry 3 \
    && apt-get purge -y build-essential \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /usr/local/bundle/cache

COPY bin ./bin
COPY lib ./lib
COPY data ./data
COPY config.ru ./
COPY README.md ./

# A non-root account, and the whole tree is readable by it. `bin/agents-fyi-mcp` stays executable
# because the same image runs the stdio server for a caller who wants it; `config.ru` is what the
# default command serves.
RUN useradd --system --uid 10004 --create-home mcp \
    && chmod +x /app/bin/agents-fyi-mcp \
    && chown -R mcp:mcp /app
USER mcp

EXPOSE 8080

# No credential in the environment, deliberately: the endpoint reads the caller's own key per
# request and stores nothing. A server-side key here would hand every remote caller the authoring
# account the corpus measures.
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:8080", "config.ru"]
