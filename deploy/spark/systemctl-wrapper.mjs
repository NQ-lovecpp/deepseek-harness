#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import net from 'node:net'

const rawArgs = process.argv.slice(2)
const userIndex = rawArgs.indexOf('--user')

if (userIndex === -1) {
  process.stderr.write('DeepSeek Harness host administration supports only systemctl --user commands.\n')
  process.exit(2)
}

const args = [...rawArgs.slice(0, userIndex), ...rawArgs.slice(userIndex + 1)]
const token = readFileSync('/run/dsh-proxy/token', 'utf8').trim()
const host = process.env.SYSTEMCTL_PROXY_HOST ?? '127.0.0.1'
const port = Number(process.env.SYSTEMCTL_PROXY_PORT ?? '8892')

const socket = net.createConnection({ host, port })
let response = ''

socket.setTimeout(65_000)
socket.on('connect', () => socket.write(`${JSON.stringify({ token, args })}\n`))
socket.on('data', (chunk) => {
  response += chunk
})
socket.on('timeout', () => socket.destroy(new Error('host systemctl proxy timed out')))
socket.on('error', (error) => {
  process.stderr.write(`host systemctl proxy: ${error.message}\n`)
  process.exitCode = 1
})
socket.on('end', () => {
  if (process.exitCode !== undefined) return
  try {
    const result = JSON.parse(response)
    if (typeof result.stdout === 'string') process.stdout.write(result.stdout)
    if (typeof result.stderr === 'string') process.stderr.write(result.stderr)
    process.exitCode = Number.isInteger(result.code) ? result.code : 1
  } catch {
    process.stderr.write('host systemctl proxy returned an invalid response.\n')
    process.exitCode = 1
  }
})
