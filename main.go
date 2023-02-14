package main

// ** Server events and meaning ** //

// ** - 'user_conn' -- User connecting to server
// ** - 'user_disconn' -- User disconnecting from server
// ** - 'user_new' -- New user account
// ** - 'user_delete' -- User account deleted
// ** - 'user_update' -- User info update

// ** - 'chat_create' -- New Chat created
// ** - 'chat_delete' -- Chat deleted
// ** - 'chat_message' -- Chat message received
// ** - 'chat_join' -- Chat joined by another user
// ** - 'chat_invite' -- Chat invite received by another user
// ** - 'chat_leave' -- Chat left by another user

import (
	"chat/logger"

	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"nhooyr.io/websocket"
)

var activeServer *server

type server struct {
	instance int
	// config   NetworkConfig
	// settings Settings
	channels syncChannels
	modules  struct {
		webserver bool
		websocket bool
		tcp       bool
	}
	httpServer *httpServer
	// tcp        *Socket_Server
	websocket *websocketServer
	dbconn    *sql.DB
}

type configServer struct {
	ServerID       string `json:"server_id"`
	DefaultChannel string `json:"default_channel"`
	TestKey        string `json:"test_key"`
	ConnType       string `json:"conn_type"`
}

type configNetwork struct {
	URL  string
	IP   string
	Port string
}
type dataPayload struct {
	Success bool   `json:"success"`
	Origin  string `json:"origin,omitempty"`
	Event   string `json:"event"`
	Data    any    `json:"data,omitempty"`
}

type syncChannels struct {
	Msg     chan dataPayload
	Dm      chan map[string]any
	Notify  chan dataPayload
	Cmd     chan dataPayload
	Conn    chan dataPayload
	Disconn chan dataPayload
}

func init() {
	// err := godotenv.Load(".env")
	// if err != nil {
	// 	panic(err)
	// }
	log.Print("\033[H\033[2J")
	var version string = "pre-alpha" // make it os.env
	logger.LogColor("CORE", "Booting..")
	logger.LogColor("CORE", fmt.Sprintf("Chat Server version: %s", version)) // make it os.env
}

func main() {
	var wg sync.WaitGroup
	// socketPort := os.Getenv("SOCKET_PORT")
	// socketTransport := os.Getenv("SOCKET_TRANSPORT")

	netConf := configNetwork{
		URL:  os.Getenv("WEB_URL"),
		IP:   os.Getenv("HOST_ADDR"),
		Port: os.Getenv("HTTP_PORT"),
	}

	dbConf := postgreConfig{
		IP:       os.Getenv("DB_ADDR"),
		Port:     os.Getenv("DB_PORT"),
		DB:       os.Getenv("DB_NAME"),
		Username: os.Getenv("DB_USER"),
		Password: os.Getenv("DB_PASSWORD"),
		SSLMode:  os.Getenv("DB_SSLMODE"),
	}

	activeServer = &server{
		instance: 1,
		channels: syncChannels{
			Msg:     make(chan dataPayload, 1),
			Dm:      make(chan map[string]any, 1),
			Notify:  make(chan dataPayload, 1),
			Cmd:     make(chan dataPayload),
			Conn:    make(chan dataPayload),
			Disconn: make(chan dataPayload),
		},
		modules: struct {
			webserver bool
			websocket bool
			tcp       bool
		}{true, true, true},
	}
	dbConn, err := connector(dbConf)
	if err != nil {
		logger.LogColor("DATABASE", "DB not found, creating..")
		dbConn, err = initDb(dbConf)
		if err != nil {
			logger.LogColor("DATABASE", "DB not found, creating..")
		}
	}
	activeServer.dbconn = dbConn
	logger.LogColor("WEBSRV", "Starting HTTP (H2C) listener..")
	activeServer.httpServer = &httpServer{
		config: netConf,
		db:     dbConn,
	}
	startHTTPServer()

	activeServer.websocket = newWebsocketServer(dbConn, activeServer.channels)
	// server.tcp = NewSocketServer(server.channels, tcp_dbconn, ip, socketPort, socketTransport)

	http.HandleFunc("/websocket/connect", activeServer.connect)

	wg.Add(1)
	go activeServer.router()
	wg.Wait()
}

func (server *server) connect(w http.ResponseWriter, r *http.Request) {
	logger.LogColor("WEBSOCK", fmt.Sprintf("Requested WebSocket - %s", r.RemoteAddr))
	session, err := sessionValidate(w, r, server.dbconn)
	if err != nil {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	userProfile, err := userRead(server.dbconn, session.UserID, true)
	if err != nil {
		logger.LogColor("WEBSOCK", "User not found, general error.")
		return
	}
	if err != nil {
		w.WriteHeader(http.StatusUnauthorized)
		logger.LogColor("WEBSOCK", fmt.Sprintf("Unhautorized session - %s", r.RemoteAddr))
		return
	}

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionNoContextTakeover})
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		logger.LogColor("WEBSOCK", fmt.Sprintf("Can't start accepting - %s", r.RemoteAddr))
		return
	}
	defer conn.Close(websocket.StatusInternalError, "Client disconnected")

	conn.SetReadLimit(2097152) // 2Mb in bytes
	notify := make(chan bool)

	client := &websocketClient{
		Msgs: make(chan []byte, server.websocket.SubscriberMessageBuffer),
		CloseSlow: func() {
			conn.Close(websocket.StatusPolicyViolation, "connection too slow to keep up with messages")
		},
	}
	server.websocket.SubscribersMu.Lock()
	server.websocket.Clients[session.UserID] = client
	server.websocket.SubscribersMu.Unlock()

	var wg sync.WaitGroup

	// TODO: Properly introduce ping detection
	ticker := time.NewTicker(time.Second * time.Duration(100000))

	// **	Sender - From CLI to SRV	**	//
	wg.Add(1)
	go func(ticker *time.Ticker) {
		defer func() {
			wg.Done()
			notify <- true
		}()
	Run:
		for {
			t, payload, err := conn.Read(r.Context())
			fmt.Printf("Payload len: %v\n", len(payload))
			if err != nil && err != io.EOF {
				statusCode := websocket.CloseStatus(err)
				if statusCode == websocket.StatusGoingAway {
					log.Println("Graceful sender shutdown")
					ticker.Stop()
					break Run
				} else {
					log.Println("Sender - Error in reading from websocket context, client closed? Check main.go")
					break Run
				}
			}
			if t.String() == "MessageText" && err == nil {
				err = server.handlePayload(payload, session.UserID)
				if err != nil {
					log.Printf("Sender - errors in broadcast: %v", err)
					// wg.Done()
					// return
				}
			}
		}
	}(ticker)

	// **		Receiver from SRV to CLI		**	//
	wg.Add(1)
	go func(ticker *time.Ticker) {
		defer func() {
			wg.Done()
		}()
		// failedPingCount := 0
		// pingTimeoutCount := 2
		// pingDelay := 5000000
	Run:
		for {
			select {
			case <-notify:
				log.Println("Receiver - got shutdown signal")
				break Run
			case payload := <-client.Msgs:
				err = writeTimeout(r.Context(), time.Second*5, conn, payload)
				if err != nil {
					break Run
				}
			case <-ticker.C:
				// if failedPingCount >= pingTimeoutCount {
				// 	fmt.Printf("Client timed out")
				// 	break Run
				// }
				t1 := time.Now().UnixMilli()
				_pingPayload := dataPayload{Success: true, Event: "ping", Data: t1}
				pingPayload, err := json.Marshal(_pingPayload)
				if err != nil {
					log.Printf("Ping - Marshaling err: %v\n", err)
				}
				err = writeTimeout(r.Context(), time.Second, conn, pingPayload)
				if err != nil {
					// pingDelay += 10
					// failedPingCount += 1
					// ticker.Reset(time.Duration(time.Second * time.Duration(pingDelay)))
					log.Printf("Ping - Sending err: %v\n", err)
					// log.Printf("Ping - Counter now %v\n", failedPingCount)
					// log.Printf("Ping - Delay now %vs\n", pingDelay)
				}
			}
		}
	}(ticker)
	err = userOnlineUpdate(server.dbconn, session.UserID, true)
	if err != nil {
		logger.LogColor("WEBSOCK", "Cannot update user status")
	}
	userInfo, err := userRead(server.dbconn, session.UserID, false)
	if err != nil {
		logger.LogColor("WEBSOCK", "Cannot get user info")
	}
	_payload := dataPayload{
		Success: true,
		Origin:  session.UserID,
		Event:   "user_conn",
		Data:    userInfo,
	}
	payload, err := json.Marshal(_payload)

	err = server.handlePayload(payload, session.UserID)
	if err != nil {
		log.Printf("Sender - error in sending user connection: %v", err)
		// wg.Done()
		// return
	}

	logger.LogColor("WEBSOCK", fmt.Sprintf("Connection successful - Username: %v", userProfile.Username))

	// * Initial client payload
	payloadFull, err := fullData(server.dbconn, session.UserID)
	if err != nil {
		log.Printf("Error in reading full data: %v\n", err)
	}
	greetingsPayload, err := json.Marshal(payloadFull)
	if err != nil {
		log.Printf("Error in initial payload: %v\n", err)
	}
	err = writeTimeout(r.Context(), time.Second*5, conn, greetingsPayload)

	if err != nil {
		log.Printf("Timeout in initial payload: %v\n", err)
	}
	log.Printf("OK - Full data sent to ID: %v\n", session.UserID)

	wg.Wait()

	server.websocket.SubscribersMu.Lock()
	delete(server.websocket.Clients, session.UserID)
	server.websocket.SubscribersMu.Unlock()
	onlineTick := time.NewTicker(time.Second * 10)
	<-onlineTick.C
	if server.websocket.Clients[session.UserID] == nil {
		err := userOnlineUpdate(server.dbconn, session.UserID, false)
		if err != nil {
			fmt.Printf("Error updating user status offline: %v\n", err)
		}
		_payload := dataPayload{
			Success: true,
			Origin:  session.UserID,
			Event:   "user_disconn",
		}
		payload, err := json.Marshal(_payload)
		if err != nil {
			fmt.Printf("Error Marshaling user_disconn payload")
		}
		err = server.handlePayload(payload, session.UserID)
		if err != nil {
			fmt.Printf("Error routing user_disconn payload")
		}
	}
}
