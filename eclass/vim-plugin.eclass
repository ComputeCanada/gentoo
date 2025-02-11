# Copyright 1999-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: vim-plugin.eclass
# @MAINTAINER:
# vim@gentoo.org
# @SUPPORTED_EAPIS: 6 7 8
# @BLURB: used for installing vim plugins
# @DESCRIPTION:
# This eclass simplifies installation of app-vim plugins into
# /usr/share/vim/vimfiles.  This is a version-independent directory
# which is read automatically by vim.  The only exception is
# documentation, for which we make a special case via vim-doc.eclass.

case ${EAPI} in
	6|7|8) ;;
	*) die "${ECLASS}: EAPI ${EAPI:-0} not supported" ;;
esac

if [[ -z ${_VIM_PLUGIN_ECLASS} ]]; then
_VIM_PLUGIN_ECLASS=1

inherit vim-doc

[[ ${EAPI} != [67] ]] && _DEFINE_VIM_PLUGIN_SRC_PREPARE=true

# @ECLASS_VARIABLE: VIM_PLUGIN_VIM_VERSION
# @DESCRIPTION:
# Minimum Vim version the plugin supports.
: ${VIM_PLUGIN_VIM_VERSION:=7.3}

DEPEND="|| ( >=app-editors/vim-${VIM_PLUGIN_VIM_VERSION}
	>=app-editors/gvim-${VIM_PLUGIN_VIM_VERSION} )"
RDEPEND="${DEPEND}"
if [[ ${PV} != 9999* ]] ; then
	SRC_URI="mirror://gentoo/${P}.tar.bz2
		https://dev.gentoo.org/~radhermit/vim/${P}.tar.bz2"
fi
SLOT="0"

if [[ ${_DEFINE_VIM_PLUGIN_SRC_PREPARE} ]]; then
# @FUNCTION: vim-plugin_src_prepare
# @USAGE:
# @DESCRIPTION:
# Moves "after/syntax" plugins to directories to avoid file collisions with
# other packages.
# Note that this function is only defined and exported in EAPIs >= 8.
vim-plugin_src_prepare() {
	debug-print-function ${FUNCNAME} "${@}"

	default_src_prepare

	# return if there's nothing to do
	[[ -d after/syntax ]] || return

	pushd after/syntax >/dev/null || die
	for file in *.vim; do
		[[ -f "${file}" ]] || continue
		mkdir "${file%.vim}" || die
		mv "${file}" "${file%.vim}/${PN}.vim" || die
	done
	popd >/dev/null || die
}
fi

# @ECLASS_VARIABLE: _VIM_PLUGIN_ALLOWED_DIRS
# @INTERNAL
# @DESCRIPTION:
# Vanilla Vim dirs.
# See /usr/share/vim/vim* for reference.
_VIM_PLUGIN_ALLOWED_DIRS=(
	after autoload colors compiler doc ftdetect ftplugin indent keymap
	macros plugin spell syntax
)

# @FUNCTION: vim-plugin_src_install
# @USAGE: [<dir>...]
# @DESCRIPTION:
# Overrides the default src_install phase. In order, this function:
#
# * installs help and documentation files.
#
# * installs all files recognized by default Vim installation and directories
#   passed to this function as arguments in "${ED}"/usr/share/vim/vimfiles.
#
# Example use:
# @CODE
# src_install() {
# 	vim-plugin_src_install syntax_checkers
# }
# @CODE
vim-plugin_src_install() {
	debug-print-function ${FUNCNAME} "${@}"

	# Install non-vim-help-docs
	einstalldocs

	# Install remainder of plugin
	insinto /usr/share/vim/vimfiles/
	local d
	case ${EAPI:-0} in
		6|7)
			for d in *; do
				[[ -d "${d}" ]] || continue
				doins -r "${d}"
			done ;;
		*)
			for d in "${_VIM_PLUGIN_ALLOWED_DIRS[@]}" "${@}"; do
				[[ -d "${d}" ]] || continue
				doins -r "${d}"
			done ;;
	esac
}

# @FUNCTION: vim-plugin_pkg_postinst
# @USAGE:
# @DESCRIPTION:
# Overrides the pkg_postinst phase for this eclass.
# The following functions are called:
#
# * update_vim_helptags
#
# * update_vim_afterscripts
#
# * display_vim_plugin_help
vim-plugin_pkg_postinst() {
	debug-print-function ${FUNCNAME} "${@}"

	update_vim_helptags # from vim-doc
	update_vim_afterscripts	# see below
	display_vim_plugin_help	# see below
}

# @FUNCTION: vim-plugin_pkg_postrm
# @DESCRIPTION:
# Overrides the pkg_postrm phase for this eclass.
# This function calls the update_vim_helptags and update_vim_afterscripts
# functions and eventually removes a bunch of empty directories.
vim-plugin_pkg_postrm() {
	debug-print-function ${FUNCNAME} "${@}"

	update_vim_helptags # from vim-doc
	update_vim_afterscripts	# see below

	# Remove empty dirs; this allows
	# /usr/share/vim to be removed if vim-core is unmerged
	find "${EPREFIX}/usr/share/vim/vimfiles" -depth -type d -exec rmdir {} \; 2>/dev/null || \
		die "rmdir failed"
}

# @FUNCTION: update_vim_afterscripts
# @USAGE:
# @DESCRIPTION:
# Creates scripts in /usr/share/vim/vimfiles/after/*
# comprised of the snippets in /usr/share/vim/vimfiles/after/*/*.d
update_vim_afterscripts() {
	debug-print-function ${FUNCNAME} "${@}"

	local d f afterdir="${EROOT}"/usr/share/vim/vimfiles/after

	# Nothing to do if the dir isn't there
	[[ -d "${afterdir}" ]] || return 0

	einfo "Updating scripts in ${afterdir}"
	find "${afterdir}" -type d -name \*.vim.d | while read d; do
		echo '" Generated by update_vim_afterscripts' > "${d%.d}" || die
		find "${d}" -name \*.vim -type f -maxdepth 1 -print0 | sort -z | \
			xargs -0 cat >> "${d%.d}" || die "update_vim_afterscripts failed"
	done

	einfo "Removing dead scripts in ${afterdir}"
	find "${afterdir}" -type f -name \*.vim | \
	while read f; do
		[[ "$(head -n 1 ${f})" == '" Generated by update_vim_afterscripts' ]] \
			|| continue
		# This is a generated file, but might be abandoned.  Check
		# if there's no corresponding .d directory, or if the
		# file's effectively empty
		if [[ ! -d "${f}.d" || -z "$(grep -v '^"' "${f}")" ]]; then
			rm "${f}" || die
		fi
	done
}

# @FUNCTION: display_vim_plugin_help
# @USAGE:
# @DESCRIPTION:
# Displays a message with the plugin's help file if one is available. Uses the
# VIM_PLUGIN_HELPFILES env var. If multiple help files are available, they
# should be separated by spaces. If no help files are available, but the env
# var VIM_PLUGIN_HELPTEXT is set, that is displayed instead. Finally, if we
# have nothing else, this functions displays a link to VIM_PLUGIN_HELPURI. An
# extra message regarding enabling filetype plugins is displayed if
# VIM_PLUGIN_MESSAGES includes the word "filetype".
display_vim_plugin_help() {
	debug-print-function ${FUNCNAME} "${@}"

	local h

	if [[ -z ${REPLACING_VERSIONS} ]]; then
		if [[ -n ${VIM_PLUGIN_HELPFILES} ]]; then
			elog " "
			elog "This plugin provides documentation via vim's help system. To"
			elog "view it, use:"
			for h in ${VIM_PLUGIN_HELPFILES}; do
				elog "    :help ${h}"
			done
			elog " "

		elif [[ -n ${VIM_PLUGIN_HELPTEXT} ]]; then
			elog " "
			while read h ; do
				elog "$h"
			done <<<"${VIM_PLUGIN_HELPTEXT}"
			elog " "

		elif [[ -n ${VIM_PLUGIN_HELPURI} ]]; then
			elog " "
			elog "Documentation for this plugin is available online at:"
			elog "    ${VIM_PLUGIN_HELPURI}"
			elog " "
		fi

		if has filetype ${VIM_PLUGIN_MESSAGES}; then
			elog "This plugin makes use of filetype settings. To enable these,"
			elog "add lines like:"
			elog "    filetype plugin on"
			elog "    filetype indent on"
			elog "to your ~/.vimrc file."
			elog " "
		fi
	fi
}

fi

# src_prepare is only exported in EAPI >= 8
[[ ${_DEFINE_VIM_PLUGIN_SRC_PREPARE} ]] && EXPORT_FUNCTIONS src_prepare

EXPORT_FUNCTIONS src_install pkg_postinst pkg_postrm
