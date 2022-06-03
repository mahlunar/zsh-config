function docspreview() {
    docker run --rm --name techdocs -w /content -v $(pwd)/:/content -p 8000:8000 -t spotify/techdocs serve -a 0.0.0.0:8000
}
