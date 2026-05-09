# Durex Tigris Store Demo

Interactive demos showing Durex GenServer state checkpointing with the [Tigris](https://www.tigrisdata.com/) object storage backend.

## Setup

1. Clone the repo and navigate to the demo directory:

```bash
git clone git@github.com:agoodway/durex.git
cd durex/demo/demo
```

2. Copy the environment template and fill in your Tigris credentials:

```bash
cp .env.sample .env
```

3. Install dependencies:

```bash
mix deps.get
```

## Demo Scripts

### Lifecycle Walkthrough

A scripted walkthrough of the full Durex lifecycle: start, modify state, checkpoint, crash, restore, and delete.

```bash
mix run priv/demo.exs
```

### Auto Counter

A long-running GenServer that increments a counter every second and checkpoints to Tigris automatically. Kill it with Ctrl-C, restart, and watch the counter resume from its last checkpoint.

```bash
mix run priv/auto_counter.exs
```
