def test_liveness_never_touches_the_database(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_readiness_reports_ok_when_database_answers(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "region": "eu-west-1"}


def test_readiness_fails_when_database_is_unreachable(client):
    client.app.state.db.healthy = False
    response = client.get("/health")
    assert response.status_code == 503


def test_every_response_carries_the_serving_region(client):
    response = client.get("/healthz")
    assert response.headers["X-Serving-Region"] == "eu-west-1"


def test_note_payload_is_validated(client):
    response = client.post("/notes", json={"title": "", "body": "x"})
    assert response.status_code == 422
