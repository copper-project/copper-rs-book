# Default recipe: serve the book locally
default:
    cd book && mdbook serve --open

# Build the book
build:
    cd book && mdbook build

# Serve the book locally with live-reload
serve:
    cd book && mdbook serve --open
