#!/bin/bash
# Copyright (c) 2021, NVIDIA CORPORATION.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

RAPIDS_MG_TOOLS_DIR=${RAPIDS_MG_TOOLS_DIR:-$(cd $(dirname $0); pwd)}
source ${RAPIDS_MG_TOOLS_DIR}/script-env.sh

# FIXME: this assumes all reports are from running pytests
ALL_REPORTS=$(ls ${TESTING_RESULTS_DIR}/pytest-results-*.txt 2> /dev/null)

# Create the html describing the build and test run
REPORT_METADATA_HTML=""
PROJECT_VERSION="unknown"
PROJECT_BUILD=""
PROJECT_CHANNEL="unknown"
PROJECT_REPO_URL="unknown"
PROJECT_REPO_BRANCH="unknown"
if [ -f $METADATA_FILE ]; then
    source $METADATA_FILE
fi
# Assume if PROJECT_BUILD is set then a conda version string should be
# created, else a git version string.
if [[ "$PROJECT_BUILD" != "" ]]; then
    REPORT_METADATA_HTML="<table>
   <tr><td>conda version</td><td>$PROJECT_VERSION</td></tr>
   <tr><td>build</td><td>$PROJECT_BUILD</td></tr>
   <tr><td>channel</td><td>$PROJECT_CHANNEL</td></tr>
</table>
<br>"
else
    REPORT_METADATA_HTML="<table>
   <tr><td>commit hash</td><td>$PROJECT_VERSION</td></tr>
   <tr><td>repo</td><td>$PROJECT_REPO_URL</td></tr>
   <tr><td>branch</td><td>$PROJECT_REPO_BRANCH</td></tr>
</table>
<br>"
fi


################################################################################
# create the html reports for each individual run (each
# pytest-results*.txt file)
if [ "$ALL_REPORTS" != "" ]; then
    for report in $ALL_REPORTS; do
        report_name=$(basename -s .txt $report)
        html=${TESTING_RESULTS_DIR}/${report_name}.html
        echo "<!doctype html>
<html>
<head>
   <title>${report_name}</title>
</head>
<body>
<h1>${report_name}</h1><br>" > $html
	echo "$REPORT_METADATA_HTML" >> $html
	echo "<table style=\"width:100%\">
   <tr>
      <th>test file</th><th>status</th><th>logs</th>
   </tr>
" >> $html
        awk '{ if($2 == "FAILED") {
                  color = "red"
              } else {
                  color = "green"
              }
              printf "<tr><td>%s</td><td style=\"color:%s\">%s</td><td><a href=%s/index.html>%s</a></td></tr>\n", $1, color, $2, $3, $3
             }' $report >> $html
        echo "</table>
    </body>
    </html>
    " >> $html
    done
fi

################################################################################
# Create a .html file for each *_log.txt file, which is just the contents
# of the log with a line number and anchor id for each line that can
# be used for sharing links to lines.
ALL_LOGS=$(find -L ${TESTING_RESULTS_DIR} -type f -name "*_log.txt" -print)

for f in $ALL_LOGS; do
    base_no_extension=$(basename ${f: 0:-4})
    html=${f: 0:-4}.html
    echo "<!doctype html>
<html>
<head>
   <title>$base_no_extension</title>
<style>
pre {
    display: inline;
    margin: 0;
}
</style>
</head>
<body>
<h1>${base_no_extension}</h1><br>
" > $html
    awk '{ print "<a id=\""NR"\" href=\"#"NR"\">"NR"</a>: <pre>"$0"</pre><br>"}' $f >> $html
    echo "</body>
</html>
" >> $html
done

################################################################################
# create the top-level report
STATUS='FAILED'
STATUS_IMG='https://img.icons8.com/cotton/80/000000/cancel--v1.png'
if [ "$ALL_REPORTS" != "" ]; then
    if ! (grep -w FAILED $ALL_REPORTS > /dev/null); then
        STATUS='PASSED'
        STATUS_IMG='https://img.icons8.com/bubbles/100/000000/approval.png'
    fi
fi
BUILD_LOG_HTML="(build log not available or build not run)"
BUILD_STATUS=""
if [ -f $BUILD_LOG_FILE ]; then
    if [ -f ${BUILD_LOG_FILE: 0:-4}.html ]; then
	BUILD_LOG_HTML="<a href=$(basename ${BUILD_LOG_FILE: 0:-4}.html)>log</a> <a href=$(basename $BUILD_LOG_FILE)>(plain text)</a>"
    else
	BUILD_LOG_HTML="<a href=$(basename $BUILD_LOG_FILE)>log</a>"
    fi
    if (tail -1 $BUILD_LOG_FILE | grep -qw "done."); then
        BUILD_STATUS="PASSED"
    else
        BUILD_STATUS="FAILED"
    fi
fi

report=${RESULTS_DIR}/report.html
echo "<!doctype html>
<html>
<head>
   <title>test report</title>
</head>
<body>
" > $report
echo "$REPORT_METADATA_HTML" >> $report
echo "<img src=\"${STATUS_IMG}\" alt=\"${STATUS}\"/> Overall status: $STATUS<br>" >> $report
echo "Build: ${BUILD_STATUS} ${BUILD_LOG_HTML}<br>" >> $report
if [ "$ALL_REPORTS" != "" ]; then
    echo "   <table style=\"width:100%\">
   <tr>
      <th>run</th><th>status</th>
   </tr>
   " >> $report
    for f in $ALL_REPORTS; do
        report_name=$(basename -s .txt $f)
        if (grep -w FAILED $f > /dev/null); then
            status="FAILED"
            color="red"
        else
            status="PASSED"
            color="green"
        fi
        echo "<tr><td><a href=${report_name}.html>${report_name}</a></td><td style=\"color:${color}\">${status}</td></tr>" >> $report
    done
    echo "</table>" >> $report
else
    echo "Tests were not run." >> $report
fi
echo "</body>
</html>
" >> $report

################################################################################
# Create an index.html for each dir (ALL_DIRS plus ".")
# This is needed since S3 (and probably others) will not show the
# contents of a hosted directory by default, but will instead return
# the index.html if present.
# The index.html will just contain links to the individual files and
# subdirs present in each dir, just as if browsing in a file explorer.
ALL_DIRS=$(find -L ${TESTING_RESULTS_DIR} -type d -printf "%P\n")

for d in "." $ALL_DIRS; do
    index=${TESTING_RESULTS_DIR}/${d}/index.html
    echo "<!doctype html>
<html>
<head>
   <title>$d</title>
</head>
<body>
<h1>${d}</h1><br>
" > $index
    for f in $(ls ${TESTING_RESULTS_DIR}/$d); do
        b=$(basename $f)
        if [[ "$b" == "index.html" ]]; then
            continue
        fi
        if [ -d "${TESTING_RESULTS_DIR}/${d}/${f}" ]; then
            echo "<a href=$b/index.html>$b</a><br>" >> $index
	# special case: if the file is a *_log.txt and has a corresponding .html
        elif [[ "${f: -8}" == "_log.txt" ]] && [[ -f "${TESTING_RESULTS_DIR}/${d}/${f: 0:-4}.html" ]]; then
	    markup="${f: 0:-4}.html"
	    plaintext=$f
            echo "<a href=$markup>$markup</a> <a href=$plaintext>(plain text)</a><br>" >> $index
	elif [[ "${f: -9}" == "_log.html" ]] && [[ -f "${TESTING_RESULTS_DIR}/${d}/${f: 0:-5}.txt" ]]; then
	    continue
	else
            echo "<a href=$b>$b</a><br>" >> $index
        fi
    done
    echo "</body>
</html>
" >> $index
done
