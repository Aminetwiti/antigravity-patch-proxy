package gateway

import (
	"database/sql"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"
)

func TestScratchSQLiteDiagnose(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "diag.db")
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer db.Close()

	if _, err := db.Exec(`CREATE TABLE steps (
		idx INTEGER, step_type INTEGER, status INTEGER,
		has_subtrajectory INTEGER, metadata BLOB, error_details BLOB,
		permissions BLOB, task_details BLOB, render_info BLOB,
		step_payload BLOB, step_format INTEGER)`); err != nil {
		t.Fatalf("create: %v", err)
	}

	meta := []byte{0x0a, 0x0c, 0x08, 0x84, 0xe2, 0xe5, 0xb3, 0x06, 0x10, 0xb8, 0xdc, 0xee, 0xf7, 0x02}
	userModern := []byte{0x9a, 0x01, 0x0b, 0x1a, 0x09, 0x0a, 0x07, 0x62, 0x6f, 0x6e, 0x6a, 0x6f, 0x75, 0x72}
	assistant := []byte{0xa2, 0x01, 0x17, 0x0a, 0x08, 0x72, 0xc3, 0xa9, 0x70, 0x6f, 0x6e, 0x73, 0x65, 0x1a, 0x09, 0x72, 0xc3, 0xa9, 0x66, 0x6c, 0xc3, 0xa9, 0x63, 0x68, 0x69}

	rows := [][]interface{}{
		{0, 14, 3, 0, meta, nil, nil, nil, nil, userModern, 0},
		{1, 15, 3, 0, meta, nil, nil, nil, nil, assistant, 0},
	}
	for _, r := range rows {
		res, err := db.Exec(`INSERT INTO steps VALUES (?,?,?,?,?,?,?,?,?,?,?)`, r...)
		if err != nil {
			t.Fatalf("insert: %v", err)
		}
		n, _ := res.RowsAffected()
		t.Logf("inserted %d row(s)\n", n)
	}

	// Count rows
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM steps").Scan(&count); err != nil {
		t.Fatalf("count: %v", err)
	}
	t.Logf("COUNT(*) = %d\n", count)

	// Raw query with the same SELECT as readSQLiteSteps
	q, err := db.Query("SELECT idx, step_type, status, metadata, step_payload FROM steps ORDER BY idx")
	if err != nil {
		t.Fatalf("query: %v", err)
	}
	defer q.Close()
	for q.Next() {
		var (
			idx, st, status int
			metadata, pl     []byte
		)
		if err := q.Scan(&idx, &st, &status, &metadata, &pl); err != nil {
			t.Logf("SCAN ERROR: %v\n", err)
			continue
		}
		t.Logf("row idx=%d step_type=%d status=%d metaLen=%d payloadLen=%d payload=%x\n", idx, st, status, len(metadata), len(pl), pl)
		text, thought := assistantTextFromPayload(pl)
		utext := userTextFromPayload(pl)
		t.Logf("  userText=%q assistantText=%q thought=%q\n", utext, text, thought)
	}
	if err := q.Err(); err != nil {
		t.Fatalf("rows err: %v", err)
	}

	// Now call readSQLiteSteps directly
	msgs, title, err := readSQLiteSteps(dbPath, "diag")
	if err != nil {
		t.Fatalf("readSQLiteSteps: %v", err)
	}
	t.Logf("readSQLiteSteps: %d msgs, title=%q\n", len(msgs), title)
	for _, m := range msgs {
		t.Logf("  msg %+v\n", m)
	}
}
