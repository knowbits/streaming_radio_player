#!/bin/bash

# Get the absolute directory of this script's folder
SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit
  pwd -P
)

DIST_DIR="$SCRIPT_DIR/dist"

# Create the "dist" subfolder if it does not exist
if [ ! -d "$DIST_DIR" ]; then
  mkdir "$DIST_DIR"
else
  # If the "dist" subfolder exists, empty it
  rm -rf "{$DIST_DIR:?}"/*
  # NOTE: Using "{:?}" to prevent it from expanding to "/" (root) in case the variable is empty
fi

# Get the absolute path of the src directory
STATIC_HTML_FOLDER=$(realpath "$SCRIPT_DIR/../src/")

# Check if the HTML directory exists
if [ ! -d "$STATIC_HTML_FOLDER" ]; then
  echo "Directory '$STATIC_HTML_FOLDER' does not exist."
  exit 1
fi

# ========================================================
# "darkhttpd": Serve static files from a folder
#
# HOME: https://unix4lyfe.org/darkhttpd/
# REPO: https://github.com/emikulic/darkhttpd
#
# darkhttpd is a simple, fast HTTP 1.1 web server for static content.
# It doesn't do CGI, SSL, or anything else complicated.
# It does what a web server should do: serve static content as fast as possible.
# darkhttpd is a single small C file, no dependencies, no crap.
#
# STEPS: Install darkhttpd on Ubuntu
#   $ sudo apt update && sudo apt -y upgrade
#   $ sudo apt install build-essential
#   $ git clone https://github.com/ryanmjacobs/darkhttpd
#   $ cd darkhttpd
#   $ make
#   $ sudo mv darkhttpd /usr/local/bin
#
# Verify installation: $ darkhttpd

# ========================================================
# Start the "darkhttpd" server to serve the static html page
# The server will run in the background on: http://localhost:8080
darkhttpd "$STATIC_HTML_FOLDER" --addr 127.0.0.1 --port 8000 &
HTTP_PID=$!

# USEFUL for DEBUGGING:
# To check if the "darkhttpd" process is running:
#    $ pgrep -f "darkhttpd . --addr 127.0.0.1 --port 8000"

# Wait until the HTTP server is responding
until curl -s http://127.0.0.1:8000 >/dev/null; do
  echo
  echo "Waiting for the 'darkhttpd' server to start..."
  sleep 1
done

# Set the CHROME_LOG_FILE environment variable
export CHROME_LOG_FILE="$DIST_DIR/chrome_debug.log"

# Run Chromium in headless mode and navigate to a web page
chromium-browser \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --virtual-time-budget=5000 \
  --disable-dev-shm-usage \
  --disable-software-rasterizer \
  --enable-logging --v=1 \
  --dump-dom 'http://127.0.0.1:8000/core_radio.html' \
  >"$DIST_DIR"/core_radio__scraped.html

# Wait for the file to be created (is this NEEDED?)
while [ ! -f "$DIST_DIR/core_radio__scraped.html" ]; do
  sleep 1
done

# ========================================================
# Kill the "darkhttpd" server
# Check if the web server process exists before killing it:
if ps -p "$HTTP_PID" >/dev/null; then
  kill -9 "$HTTP_PID"
fi

# ========================================================
# Now remove the parts of the JavaScript that cannot be part of the "scraped" version of the loaded page

# Remove the "streams" array and preceding comment block:
#
sed -i '/\/\* SECTION_TO_REMOVE_1__START \*\//,/\/\* SECTION_TO_REMOVE_1__END \*\//c\/* for loop removed by the "web scraping" shell script */' \
  "$DIST_DIR/core_radio__scraped.html"

# Remove the "    streams.forEach(..." loop, and replace it with the string "INSERT_NEW_SCRIPT_HERE"
#
sed -i '/\/\* SECTION_TO_REMOVE_2__START \*\//,/\/\* SECTION_TO_REMOVE_2__END \*\//c\INSERT_NEW_SCRIPT_HERE' \
  "$DIST_DIR/core_radio__scraped.html"

# ========================================================
# Now replace the string "INSERT_NEW_SCRIPT_HERE" with a minmal Javascript (adds an "event handler" to all buttons)
# that adds event handlers to all the "audio stream buttons" on the scraped HTML page:

# STEP 1: Keep the "new" Javascript in a variable
#
NEW_SCRIPT=$(
  cat <<'EOF'
      /* The web scraping script replaced the original DOM-generating Javascript with this minimal script: */

      // PURPOSE: Add an event handler to all buttons

      // Get all buttons
      const buttons = document.getElementsByTagName('button');

      // Loop through buttons and add event listener
      for (let i = 0; i < buttons.length; i++) {
        const audio = buttons[i].previousElementSibling;
        const url = buttons[i].getAttribute("title");

        // Check if the URL is not undefined or empty
        if (url) {
          buttons[i].addEventListener("click", function () {
            handleButtonClick(this, audio, url);
          });
        } else {
          console.error(`Button ${i} does not have a valid URL`);
        }
      }
EOF
)

# Save the script into a variable.
# The "awk" converts the multi-line string into a single-line string where newline characters are represented as \\n.
#
NEW_SCRIPT_SINGLE_LINE=$(echo "$NEW_SCRIPT" | awk '{ printf "%s\\n", $0 }' ORS='')

# Use sed to replace the placeholder with the new script
#
sed -i "s|INSERT_NEW_SCRIPT_HERE|$NEW_SCRIPT_SINGLE_LINE|g" "$DIST_DIR/core_radio__scraped.html"

# ========================================================
# USEFUL: Validate your HTML documents: http://validator.w3.org/nu/

# ========================================================
# Pretty print the resulting HTML file using "tidy".
#
# ABOUT: https://www.html-tidy.org/
#        Check, correct, and pretty-print HTML(5) files
#
# NOTE: TO install "tidy" on Ubuntu: "$ sudo apt-get install tidy"
#
# tidy -i -w 120 -m "$DIST_DIR/core_radio__scraped.html"

# ========================================================
# Pretty print the resulting HTML file using "prettier" (JavaScript).
#
# ABOUT: https://github.com/prettier/prettier
#        Pretty-prints HTML 5 files.
#        "Prettier is an opinionated code formatter."
#
# NOTE: To install "prettier" on Ubuntu (requires npm):
#       "$ sudo npm install --global prettier"
#       This will install Prettier globally, so you can use it from any directory on your system.
#
prettier "$DIST_DIR/core_radio__scraped.html" >"$DIST_DIR/core_radio__scraped__pretty_printed.html"

# ========================================================
# Echo the result: Location of the final scraped HTML file
echo
echo ============================================
echo "Scraped the loaded web page (with innerHTML from JavaScript))."
echo "Result was saved in: '$DIST_DIR/core_radio__scraped.html'"

# Instructions to view the file
echo
echo "To view the resulting html file, run: "
echo "   $ open $DIST_DIR/core_radio__scraped.html"
echo ============================================
echo

# JUST IN CASE: Instructions to search the Chromium log file for "ERROR:" or "WARNING:"
echo ============================================
echo "To search the log file for error or warning, run: "
echo "   grep -E 'ERROR:|WARNING:' $DIST_DIR/chrome_debug.log"
echo ============================================
echo
