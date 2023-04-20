import jenkins.*
import jenkins.model.*
import hudson.*
import hudson.model.*

def gitURL = "https://github.com/stolostron/acmqe-mcn-test.git"
def command = "git ls-remote -h " + gitURL
def proc = command.execute()
proc.waitFor()

if (proc.exitValue() != 0) {
    println "Error, ${proc.err.text}"
    System.exit(0)
}

def branches = proc.in.text.readLines().collect {
    it.replaceAll(".*heads\\/", "")
}
return branches.join(",")
