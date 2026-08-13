package main

import (
	"bufio"
	"fmt"
	"os/exec"
)

func main() {
	cmd := exec.Command("cmd.exe", "/c", "ssh", "-p", "443", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "-R", "0:127.0.0.1:8080", "free@a.pinggy.io")
	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()
	cmd.Start()

	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			fmt.Println("STDOUT:", scanner.Text())
		}
	}()

	scanner2 := bufio.NewScanner(stderr)
	for scanner2.Scan() {
		fmt.Println("STDERR:", scanner2.Text())
	}

	cmd.Wait()
}
