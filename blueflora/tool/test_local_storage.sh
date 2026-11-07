#!/usr/bin/env bash
# Preparación reproducible de FFI, sin sudo ni instalación de bibliotecas.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

if [[ "$(uname -s)" == Linux ]]; then
  unversioned=''
  for candidate in /lib/libsqlite3.so /usr/lib/libsqlite3.so \
      /lib/*-linux-gnu/libsqlite3.so /usr/lib/*-linux-gnu/libsqlite3.so; do
    if [[ -r "$candidate" ]]; then
      unversioned="$candidate"
      break
    fi
  done
  if [[ -z "$unversioned" ]]; then
    versioned=''
    for candidate in /lib/libsqlite3.so.0 /usr/lib/libsqlite3.so.0 \
        /lib/*-linux-gnu/libsqlite3.so.0 /usr/lib/*-linux-gnu/libsqlite3.so.0; do
      if [[ -r "$candidate" ]]; then
        versioned="$(readlink -f -- "$candidate")"
        break
      fi
    done
    if [[ -z "$versioned" ]]; then
      printf '%s\n' 'No se encontró SQLite nativo. No se instaló ningún componente.' >&2
      exit 1
    fi
    library_directory="$PWD/.dart_tool/blueflora-test-libs"
    library_link="$library_directory/libsqlite3.so"
    mkdir -p -- "$library_directory"
    if [[ -e "$library_link" || -L "$library_link" ]]; then
      if [[ ! -L "$library_link" || "$(readlink -f -- "$library_link")" != "$versioned" ]]; then
        printf '%s\n' 'El enlace FFI existente no coincide; no se sobrescribió.' >&2
        exit 1
      fi
    else
      ln -s -- "$versioned" "$library_link"
    fi
    export LD_LIBRARY_PATH="$library_directory${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    printf 'FFI de pruebas: %s -> %s\n' "$library_link" "$versioned"
  fi
fi

exec "${BLUEFLORA_FLUTTER_BIN:-flutter}" test --no-pub "$@"
