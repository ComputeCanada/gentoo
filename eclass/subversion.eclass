# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: subversion.eclass
# @MAINTAINER:
# Akinori Hattori <hattya@gentoo.org>
# @AUTHOR:
# Original Author: Akinori Hattori <hattya@gentoo.org>
# @SUPPORTED_EAPIS: 7 8
# @BLURB: Fetch software sources from subversion repositories
# @DESCRIPTION:
# The subversion eclass provides functions to fetch software sources
# from subversion repositories.

case ${EAPI} in
	7|8) inherit estack ;;
	*) die "${ECLASS}: EAPI ${EAPI:-0} not supported" ;;
esac

if [[ -z ${_SUBVERSION_ECLASS} ]]; then
_SUBVERSION_ECLASS=1

PROPERTIES+=" live"

BDEPEND="
	dev-vcs/subversion[http(+)]
	net-misc/rsync"

# @ECLASS_VARIABLE: ESVN_STORE_DIR
# @USER_VARIABLE
# @DESCRIPTION:
# subversion sources store directory. Users may override this in /etc/portage/make.conf
[[ -z ${ESVN_STORE_DIR} ]] && ESVN_STORE_DIR="${PORTAGE_ACTUAL_DISTDIR:-${DISTDIR}}/svn-src"

# @ECLASS_VARIABLE: ESVN_FETCH_CMD
# @DESCRIPTION:
# subversion checkout command
ESVN_FETCH_CMD="svn checkout"

# @ECLASS_VARIABLE: ESVN_UPDATE_CMD
# @DESCRIPTION:
# subversion update command
ESVN_UPDATE_CMD="svn update"

# @ECLASS_VARIABLE: ESVN_SWITCH_CMD
# @DESCRIPTION:
# subversion switch command
ESVN_SWITCH_CMD="svn switch"

# @ECLASS_VARIABLE: ESVN_OPTIONS
# @DESCRIPTION:
# the options passed to checkout or update. If you want a specific revision see
# ESVN_REPO_URI instead of using -rREV.
ESVN_OPTIONS="${ESVN_OPTIONS:-}"

# @ECLASS_VARIABLE: ESVN_REPO_URI
# @DESCRIPTION:
# repository uri
#
# e.g. http://example.org/trunk, svn://example.org/branch/foo@1234
#
# supported URI schemes:
#   http://
#   https://
#   svn://
#   svn+ssh://
#   file://
#
# to peg to a specific revision, append @REV to the repo's uri
ESVN_REPO_URI="${ESVN_REPO_URI:-}"

# @ECLASS_VARIABLE: ESVN_REVISION
# @DESCRIPTION:
# User configurable revision checkout or update to from the repository
#
# Useful for live svn or trunk svn ebuilds allowing the user to peg
# to a specific revision
#
# Note: This should never be set in an ebuild!
ESVN_REVISION="${ESVN_REVISION:-}"

# @ECLASS_VARIABLE: ESVN_USER
# @DESCRIPTION:
# User name
ESVN_USER="${ESVN_USER:-}"

# @ECLASS_VARIABLE: ESVN_PASSWORD
# @DESCRIPTION:
# Password
ESVN_PASSWORD="${ESVN_PASSWORD:-}"

# @ECLASS_VARIABLE: ESVN_PROJECT
# @DESCRIPTION:
# project name of your ebuild (= name space)
#
# subversion eclass will check out the subversion repository like:
#
#   ${ESVN_STORE_DIR}/${ESVN_PROJECT}/${ESVN_REPO_URI##*/}
#
# so if you define ESVN_REPO_URI as http://svn.collab.net/repo/svn/trunk or
# http://svn.collab.net/repo/svn/trunk/. and PN is subversion-svn.
# it will check out like:
#
#   ${ESVN_STORE_DIR}/subversion/trunk
#
# this is not used in order to declare the name of the upstream project.
# so that you can declare this like:
#
#   # jakarta commons-loggin
#   ESVN_PROJECT=commons/logging
#
# default: ${PN/-svn}.
ESVN_PROJECT="${ESVN_PROJECT:-${PN/-svn}}"

# @ECLASS_VARIABLE: ESVN_RESTRICT
# @DESCRIPTION:
# this should be a space delimited list of subversion eclass features to
# restrict.
#   export)
#     don't export the working copy to S.
ESVN_RESTRICT="${ESVN_RESTRICT:-}"

# @ECLASS_VARIABLE: ESVN_OFFLINE
# @USER_VARIABLE
# @DEFAULT_UNSET
# @DESCRIPTION:
# Set this variable to a non-empty value to disable the automatic updating of
# an svn source tree. This is intended to be set outside the subversion source
# tree by users.
ESVN_OFFLINE="${ESVN_OFFLINE:-${EVCS_OFFLINE}}"

# @ECLASS_VARIABLE: ESVN_UMASK
# @USER_VARIABLE
# @DESCRIPTION:
# Set this variable to a custom umask. This is intended to be set by users.
# By setting this to something like 002, it can make life easier for people
# who do development as non-root (but are in the portage group), and then
# switch over to building with FEATURES=userpriv.  Or vice-versa.  Shouldn't
# be a security issue here as anyone who has portage group write access
# already can screw the system over in more creative ways.
ESVN_UMASK="${ESVN_UMASK:-${EVCS_UMASK}}"

# @ECLASS_VARIABLE: ESVN_UP_FREQ
# @USER_VARIABLE
# @DESCRIPTION:
# Set the minimum number of hours between svn up'ing in any given svn module. This is particularly
# useful for split KDE ebuilds where we want to ensure that all submodules are compiled for the same
# revision. It should also be kept user overrideable.
ESVN_UP_FREQ="${ESVN_UP_FREQ:=}"

# @ECLASS_VARIABLE: ESCM_LOGDIR
# @USER_VARIABLE
# @DESCRIPTION:
# User configuration variable. If set to a path such as e.g. /var/log/scm any
# package inheriting from subversion.eclass will record svn revision to
# ${CATEGORY}/${PN}.log in that path in pkg_preinst. This is not supposed to be
# set by ebuilds/eclasses. It defaults to empty so users need to opt in.
ESCM_LOGDIR="${ESCM_LOGDIR:=}"

# @FUNCTION: subversion_fetch
# @USAGE: [repo_uri] [destination]
# @DESCRIPTION:
# Wrapper function to fetch sources from subversion via svn checkout or svn update,
# depending on whether there is an existing working copy in ${ESVN_STORE_DIR}.
#
# Can take two optional parameters:
#   repo_uri    - a repository URI. default is ESVN_REPO_URI.
#   destination - a check out path in S.
subversion_fetch() {
	local repo_uri="$(subversion__get_repository_uri "${1:-${ESVN_REPO_URI}}")"
	local revision="$(subversion__get_peg_revision "${1:-${ESVN_REPO_URI}}")"
	local S_dest="${2}"

	if [[ -z ${repo_uri} ]]; then
		die "${ECLASS}: ESVN_REPO_URI (or specified URI) is empty."
	fi

	[[ -n ${ESVN_REVISION} ]] && revision="${ESVN_REVISION}"

	# check for the scheme
	local scheme="${repo_uri%%:*}"
	case "${scheme}" in
		http|https)
			;;
		svn|svn+ssh)
			;;
		file)
			;;
		*)
			die "${ECLASS}: fetch from '${scheme}' is not yet implemented."
			;;
	esac

	addread "/etc/subversion"
	addwrite "${ESVN_STORE_DIR}"

	if [[ -n ${ESVN_UMASK} ]]; then
		eumask_push "${ESVN_UMASK}"
	fi

	if [[ ! -d ${ESVN_STORE_DIR} ]]; then
		debug-print "${FUNCNAME}: initial checkout. creating subversion directory"
		mkdir -m 775 -p "${ESVN_STORE_DIR}" || die "${ECLASS}: can't mkdir ${ESVN_STORE_DIR}."
	fi

	pushd "${ESVN_STORE_DIR}" >/dev/null || die "${ECLASS}: can't chdir to ${ESVN_STORE_DIR}"

	local wc_path="$(subversion__get_wc_path "${repo_uri}")"
	local options="${ESVN_OPTIONS} --config-dir ${ESVN_STORE_DIR}/.subversion"

	[[ -n ${revision} ]] && options="${options} -r ${revision}"

	if [[ ${ESVN_OPTIONS} == *-r* ]]; then
		ewarn "\${ESVN_OPTIONS} contains -r, this usage is unsupported. Please"
		ewarn "see \${ESVN_REPO_URI}"
	fi

	if has_version ">=dev-vcs/subversion-1.6.0"; then
		options="${options} --config-option=config:auth:password-stores="
	fi

	debug-print "${FUNCNAME}: wc_path = \"${wc_path}\""
	debug-print "${FUNCNAME}: ESVN_OPTIONS = \"${ESVN_OPTIONS}\""
	debug-print "${FUNCNAME}: options = \"${options}\""

	if [[ ! -d ${wc_path}/.svn ]]; then
		if [[ -n ${ESVN_OFFLINE} ]]; then
			ewarn "ESVN_OFFLINE cannot be used when there is no existing checkout."
		fi
		# first check out
		einfo "subversion check out start -->"
		einfo "     repository: ${repo_uri}${revision:+@}${revision}"

		debug-print "${FUNCNAME}: ${ESVN_FETCH_CMD} ${options} ${repo_uri}"

		mkdir -m 775 -p "${ESVN_PROJECT}" || die "${ECLASS}: can't mkdir ${ESVN_PROJECT}."
		cd "${ESVN_PROJECT}" || die "${ECLASS}: can't chdir to ${ESVN_PROJECT}"
		if [[ -n ${ESVN_USER} ]]; then
			${ESVN_FETCH_CMD} ${options} --username "${ESVN_USER}" --password "${ESVN_PASSWORD}" "${repo_uri}" || die "${ECLASS}: can't fetch to ${wc_path} from ${repo_uri}."
		else
			${ESVN_FETCH_CMD} ${options} "${repo_uri}" || die "${ECLASS}: can't fetch to ${wc_path} from ${repo_uri}."
		fi

	elif [[ -n ${ESVN_OFFLINE} ]]; then
		svn upgrade "${wc_path}" &>/dev/null
		svn cleanup "${wc_path}" &>/dev/null
		subversion_wc_info "${repo_uri}" || die "${ECLASS}: unknown problem occurred while accessing working copy."

		if [[ -n ${ESVN_REVISION} && ${ESVN_REVISION} != ${ESVN_WC_REVISION} ]]; then
			die "${ECLASS}: You requested off-line updating and revision ${ESVN_REVISION} but only revision ${ESVN_WC_REVISION} is available locally."
		fi
		einfo "Fetching disabled: Using existing repository copy at revision ${ESVN_WC_REVISION}."
	else
		svn upgrade "${wc_path}" &>/dev/null
		svn cleanup "${wc_path}" &>/dev/null
		subversion_wc_info "${repo_uri}" || die "${ECLASS}: unknown problem occurred while accessing working copy."

		local esvn_up_freq=
		if [[ -n ${ESVN_UP_FREQ} ]]; then
			if [[ -n ${ESVN_UP_FREQ//[[:digit:]]} ]]; then
				die "${ECLASS}: ESVN_UP_FREQ must be an integer value corresponding to the minimum number of hours between svn up."
			elif [[ -z $(find "${wc_path}/.svn/entries" -mmin "+$((ESVN_UP_FREQ*60))") ]]; then
				einfo "Fetching disabled since ${ESVN_UP_FREQ} hours has not passed since last update."
				einfo "Using existing repository copy at revision ${ESVN_WC_REVISION}."
				esvn_up_freq=no_update
			fi
		fi

		if [[ -z ${esvn_up_freq} ]]; then
			if [[ ${ESVN_WC_UUID} != $(subversion__svn_info "${repo_uri}" "Repository UUID") ]]; then
				# UUID mismatch. Delete working copy and check out it again.
				einfo "subversion recheck out start -->"
				einfo "     old UUID: ${ESVN_WC_UUID}"
				einfo "     new UUID: $(subversion__svn_info "${repo_uri}" "Repository UUID")"
				einfo "     repository: ${repo_uri}${revision:+@}${revision}"

				rm -rf "${ESVN_PROJECT}" || die

				debug-print "${FUNCNAME}: ${ESVN_FETCH_CMD} ${options} ${repo_uri}"

				mkdir -m 775 -p "${ESVN_PROJECT}" || die "${ECLASS}: can't mkdir ${ESVN_PROJECT}."
				cd "${ESVN_PROJECT}" || die "${ECLASS}: can't chdir to ${ESVN_PROJECT}"
				if [[ -n ${ESVN_USER} ]]; then
					${ESVN_FETCH_CMD} ${options} --username "${ESVN_USER}" --password "${ESVN_PASSWORD}" "${repo_uri}" || die "${ECLASS}: can't fetch to ${wc_path} from ${repo_uri}."
				else
					${ESVN_FETCH_CMD} ${options} "${repo_uri}" || die "${ECLASS}: can't fetch to ${wc_path} from ${repo_uri}."
				fi
			elif [[ ${ESVN_WC_URL} != $(subversion__get_repository_uri "${repo_uri}") ]]; then
				einfo "subversion switch start -->"
				einfo "     old repository: ${ESVN_WC_URL}@${ESVN_WC_REVISION}"
				einfo "     new repository: ${repo_uri}${revision:+@}${revision}"

				debug-print "${FUNCNAME}: ${ESVN_SWITCH_CMD} ${options} ${repo_uri}"

				cd "${wc_path}" || die "${ECLASS}: can't chdir to ${wc_path}"
				if [[ -n ${ESVN_USER} ]]; then
					${ESVN_SWITCH_CMD} ${options} --username "${ESVN_USER}" --password "${ESVN_PASSWORD}" ${repo_uri} || die "${ECLASS}: can't update ${wc_path} from ${repo_uri}."
				else
					${ESVN_SWITCH_CMD} ${options} ${repo_uri} || die "${ECLASS}: can't update ${wc_path} from ${repo_uri}."
				fi
			else
				# update working copy
				einfo "subversion update start -->"
				einfo "     repository: ${repo_uri}${revision:+@}${revision}"

				debug-print "${FUNCNAME}: ${ESVN_UPDATE_CMD} ${options}"

				cd "${wc_path}" || die "${ECLASS}: can't chdir to ${wc_path}"
				if [[ -n ${ESVN_USER} ]]; then
					${ESVN_UPDATE_CMD} ${options} --username "${ESVN_USER}" --password "${ESVN_PASSWORD}" || die "${ECLASS}: can't update ${wc_path} from ${repo_uri}."
				else
					${ESVN_UPDATE_CMD} ${options} || die "${ECLASS}: can't update ${wc_path} from ${repo_uri}."
				fi
			fi

			# export updated information for the working copy
			subversion_wc_info "${repo_uri}" || die "${ECLASS}: unknown problem occurred while accessing working copy."
		fi
	fi

	if [[ -n ${ESVN_UMASK} ]]; then
		eumask_pop
	fi

	einfo "   working copy: ${wc_path}"

	if ! has "export" ${ESVN_RESTRICT}; then
		cd "${wc_path}" || die "${ECLASS}: can't chdir to ${wc_path}"

		local S="${S}/${S_dest}"
		mkdir -p "${S}"

		# export to the ${WORKDIR}
		#*  "svn export" has a bug.  see https://bugs.gentoo.org/119236
		#* svn export . "${S}" || die "${ECLASS}: can't export to ${S}."
		rsync -rlpgo --exclude=".svn/" . "${S}" || die "${ECLASS}: can't export to ${S}."
	fi

	popd >/dev/null
	echo
}

# @FUNCTION: subversion_wc_info
# @USAGE: [repo_uri]
# @RETURN: ESVN_WC_URL, ESVN_WC_ROOT, ESVN_WC_UUID, ESVN_WC_REVISION and ESVN_WC_PATH
# @DESCRIPTION:
# Get svn info for the specified repo_uri. The default repo_uri is ESVN_REPO_URI.
#
# The working copy information on the specified repository URI are set to
# ESVN_WC_* variables.
subversion_wc_info() {
	local repo_uri="$(subversion__get_repository_uri "${1:-${ESVN_REPO_URI}}")"
	local wc_path="$(subversion__get_wc_path "${repo_uri}")"

	debug-print "${FUNCNAME}: repo_uri = ${repo_uri}"
	debug-print "${FUNCNAME}: wc_path = ${wc_path}"

	if [[ ! -d ${wc_path} ]]; then
		return 1
	fi

	export ESVN_WC_URL="$(subversion__svn_info "${wc_path}" "URL")"
	export ESVN_WC_ROOT="$(subversion__svn_info "${wc_path}" "Repository Root")"
	export ESVN_WC_UUID="$(subversion__svn_info "${wc_path}" "Repository UUID")"
	export ESVN_WC_REVISION="$(subversion__svn_info "${wc_path}" "Revision")"
	export ESVN_WC_PATH="${wc_path}"
}

# @FUNCTION: subversion_src_unpack
# @DESCRIPTION:
# Default src_unpack. Fetch.
subversion_src_unpack() {
	subversion_fetch || die "${ECLASS}: unknown problem occurred in subversion_fetch."
}

# @FUNCTION: subversion_pkg_preinst
# @USAGE: [repo_uri]
# @DESCRIPTION:
# Log the svn revision of source code. Doing this in pkg_preinst because we
# want the logs to stick around if packages are uninstalled without messing with
# config protection.
subversion_pkg_preinst() {
	local pkgdate=$(date "+%Y%m%d %H:%M:%S")
	if [[ -n ${ESCM_LOGDIR} ]]; then
		local dir="${EROOT}${ESCM_LOGDIR}/${CATEGORY}"
		if [[ ! -d ${dir} ]]; then
			mkdir -p "${dir}" || eerror "Failed to create '${dir}' for logging svn revision"
		fi
		local logmessage="svn: ${pkgdate} - ${PF}:${SLOT} was merged at revision ${ESVN_WC_REVISION}"
		if [[ -d ${dir} ]]; then
			echo "${logmessage}" >>"${dir}/${PN}.log"
		else
			eerror "Could not log the message '${logmessage}' to '${dir}/${PN}.log'"
		fi
	fi
}

## -- Private Functions

# @FUNCTION: subversion__svn_info
# @USAGE: <target> <key name>
# @INTERNAL
subversion__svn_info() {
	local target="${1}"
	local key="${2}"

	env LC_ALL=C svn info ${options} --username "${ESVN_USER}" --password "${ESVN_PASSWORD}" "${target}" \
		| grep -i "^${key}" \
		| cut -d" " -f2-
}

# @FUNCTION: subversion__get_repository_uri
# @USAGE: <repository URI>
# @INTERNAL
subversion__get_repository_uri() {
	local repo_uri="${1}"

	debug-print "${FUNCNAME}: repo_uri = ${repo_uri}"
	if [[ -z ${repo_uri} ]]; then
		die "${ECLASS}: ESVN_REPO_URI (or specified URI) is empty."
	fi
	# delete trailing slash
	if [[ -z ${repo_uri##*/} ]]; then
		repo_uri="${repo_uri%/}"
	fi
	repo_uri="${repo_uri%@*}"

	echo "${repo_uri}"
}

# @FUNCTION: subversion__get_wc_path
# @USAGE: <repository URI>
# @INTERNAL
subversion__get_wc_path() {
	local repo_uri="$(subversion__get_repository_uri "${1}")"

	debug-print "${FUNCNAME}: repo_uri = ${repo_uri}"

	echo "${ESVN_STORE_DIR}/${ESVN_PROJECT}/${repo_uri##*/}"
}

# @FUNCTION: subversion__get_peg_revision
# @USAGE: <repository URI>
# @INTERNAL
subversion__get_peg_revision() {
	local repo_uri="${1}"
	local peg_rev=

	debug-print "${FUNCNAME}: repo_uri = ${repo_uri}"
	# repo_uri has peg revision?
	if [[ ${repo_uri} == *@* ]]; then
		peg_rev="${repo_uri##*@}"
		debug-print "${FUNCNAME}: peg_rev = ${peg_rev}"
	else
		debug-print "${FUNCNAME}: repo_uri does not have a peg revision."
	fi

	echo "${peg_rev}"
}

fi

EXPORT_FUNCTIONS src_unpack pkg_preinst
