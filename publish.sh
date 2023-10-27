#!/bin/sh

set -e

npm version patch
npm publish
