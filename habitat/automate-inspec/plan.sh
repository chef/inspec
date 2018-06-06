pkg_name=automate-inspec
pkg_origin=chef
pkg_version=$(cat "$PLAN_CONTEXT/../../VERSION")
pkg_description="InSpec packaged for use in Chef Automate"
pkg_upstream_url=https://www.inspec.io/
pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
pkg_license=("Chef-MLSA")
pkg_deps=(
  core/busybox-static
  core/cacerts
  core/coreutils
  core/libxml2
  core/libxslt
  core/net-tools
  core/ruby

  # Needed for some InSpec resources
  core/bind
  core/curl
  core/docker
  core/git
  core/less
  core/mysql-client
  core/netcat
  # See https://github.com/chef/inspec/issues/3002
  core/postgresql/9.6.8
)
pkg_build_deps=(
  core/gcc
  core/git
  core/make
  core/readline
  core/sed
)
pkg_bin_dirs=(bin)

do_prepare() {
  export GEM_HOME="$pkg_prefix/lib"
  build_line "Setting GEM_HOME=$GEM_HOME"
  export GEM_PATH="$GEM_HOME"
  build_line "Setting GEM_PATH=$GEM_PATH"
}

do_unpack() {
  export INSPEC_SRC_CACHE="$HAB_CACHE_SRC_PATH/$pkg_dirname/inspec"
  export INSPEC_SCAP_SRC_CACHE="$HAB_CACHE_SRC_PATH/$pkg_dirname/inspec-scap"

  build_line "Copying InSpec source to $INSPEC_SRC_CACHE"
  mkdir -pv "$INSPEC_SRC_CACHE"
  cp -R "$PLAN_CONTEXT/../../" "$INSPEC_SRC_CACHE"

  build_line "Cloning InSpec SCAP source to $INSPEC_SCAP_SRC_CACHE"
  mkdir -pv "$INSPEC_SCAP_SRC_CACHE"
  git clone --depth=1 https://$GITHUB_TOKEN@github.com/chef/inspec-scap.git $INSPEC_SCAP_SRC_CACHE
}

do_build() {
  build_line "Building InSpec gem"
  pushd "$INSPEC_SRC_CACHE" > /dev/null
    gem build inspec.gemspec
  popd > /dev/null

  build_line "Building InSpec SCAP gem"
  pushd "$INSPEC_SCAP_SRC_CACHE" > /dev/null
    gem build inspec-scap.gemspec
  popd > /dev/null
}

do_install() {
  build_line "Installing InSpec gem"
  pushd "$INSPEC_SRC_CACHE" > /dev/null
    gem install inspec-*.gem --no-document
  popd > /dev/null

  build_line "Installing InSpec SCAP gem"
  pushd "$INSPEC_SCAP_SRC_CACHE" > /dev/null
    gem install inspec-scap-*.gem --no-document
  popd > /dev/null

  wrap_inspec_bin
}

# Need to wrap the InSpec binary to ensure GEM_HOME/GEM_PATH is correct
wrap_inspec_bin() {
  local bin="$pkg_prefix/bin/inspec"
  local real_bin="$GEM_HOME/gems/inspec-${pkg_version}/bin/inspec"
  build_line "Adding wrapper $bin to $real_bin"
  cat <<EOF > "$bin"
#!$(pkg_path_for busybox-static)/bin/sh
export SSL_CERT_FILE=$(pkg_path_for cacerts)/ssl/cert.pem
set -e
export GEM_HOME="$GEM_HOME"
export GEM_PATH="$GEM_PATH"

if [[ -z \$MLSA_ACCEPTED ]]; then
  cat <<EOL
=========================================================================
Use of this Software is subject to the terms of the Chef Online Master
License and Services Agreement. You can find the latest copy of the agreement here:

https://www.chef.io/online-master-agreement
=========================================================================
EOL
  echo 'Set the environment variable MLSA_ACCEPTED to true to accept'
  exit 19  
fi

exec $(pkg_path_for core/ruby)/bin/ruby $real_bin \$@
EOF
  chmod -v 755 "$bin"
}

do_strip() {
  return 0
}
