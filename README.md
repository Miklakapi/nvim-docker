# nvim-docker — project notes

## Goal

Build a small and lightweight Docker plugin for Neovim.

The plugin should focus only on the most useful daily actions. It is not meant to replace Docker Desktop, lazydocker, or other advanced Docker management tools.

## Main views

The plugin should have two modes:

* `DockerCompose` — show containers from the current project
* `Docker` — show all containers available in the current Docker environment

## Interface idea

Use only one large floating window.

The popup should contain two panels:

* container list on the left
* live logs on the right

The container list should show:

* status icon
* container name
* service or image
* current status
* ports

Example status icons:

```text
● running
◐ restarting
○ stopped
× failed
```

The first running container can be selected automatically when the popup opens.

Moving through the list should not change logs immediately. Pressing `Enter` should confirm which container is shown in the logs panel.

## Live behaviour

The container list should update automatically when the Docker state changes.

The logs panel should follow the selected container live.

If a Compose container is recreated, the plugin should try to continue following the same service.

Manual refresh should not be required during normal use.

## Planned actions

```text
j / k    move through containers
Enter    show logs for selected container
s        start container
x        stop container
r        restart container
Tab      switch between container list and logs
q        close popup
```

The logs panel should support normal Neovim scrolling.

## Version 1.0 scope

Version 1.0 should include:

* Docker mode
* Docker Compose mode
* one floating interface
* live container state
* live logs
* start
* stop
* restart
* clear status icons
* basic container information

## Core idea

Open one lightweight popup, see containers immediately, follow logs, and perform the most common actions without leaving Neovim.
