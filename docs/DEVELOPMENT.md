# Development evidence

2026-09-07: initialized with `moon new moon-firmware --user SongYZZZ --name moon-firmware`.
The installed toolchain generated modern moon.mod and moon.pkg files. CLI help for
check, test, fmt, publish, package, bench and doc was inspected before implementation.
`moon doc Bytes` confirmed the immutable Bytes and slicing APIs in the installed core.

The initial PATH toolchain was moon 0.1.20260819 / moonc 0.10.9. A newer official
toolchain was installed under the ignored `.tools/moon` directory after the current
`moonbitlang/async` package and hosted formatter required moon 0.1.20260827 / moonc
0.10.11. The bundled core was built for native. No global user installation changed.

GitHub authentication was corrected and verified with `gh api user` as SongYZZZ.
The exact public remote is https://github.com/SongYZZZ/moon-firmware. Mooncakes still
reports hjn0123, so packaging is tested but publishing under the wrong owner is blocked.

CI setup action v1.22 was verified in its upstream README and action metadata on
2026-09-07: https://github.com/hustcer/setup-moonbit. The first hosted run exposed a
missing clean-runner registry update; CI now runs `moon update` before dependency-aware
checks. Hosted success is recorded only after a green run, never inferred locally.
