from fastapi import Request


def resources(request: Request):
    return request.app.state.resource_repository
