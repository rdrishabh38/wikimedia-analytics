# app/consumer.py (Final Resilient Version)
from datetime import datetime
import json
import os
import requests
import time
from confluent_kafka import Producer, KafkaError

print("--- Starting Wikimedia Consumer (Resilient) ---")

# --- Connection Details ---
KAFKA_BROKER = os.environ.get("KAFKA_BROKER")
KAFKA_TOPIC = os.environ.get("KAFKA_TOPIC")
WIKIMEDIA_STREAM_URL = 'https://stream.wikimedia.org/v2/stream/page-move'
HEADERS = {
    'Accept': 'text/event-stream',
    'User-Agent': 'WikimediaPOC/0.1 (rishabh@example.com)'
}

# --- Kafka Producer Setup (with Retry Loop) ---
producer = None
while producer is None:
    try:
        print(f"Attempting to connect to Kafka at {KAFKA_BROKER}...")
        producer_conf = {
            'bootstrap.servers': KAFKA_BROKER,
            'client.id': 'wikimedia-producer'
        }
        producer = Producer(producer_conf)
        print("✅ Successfully connected to Kafka!")
    except KafkaError as e:
        print(f"❌ Kafka connection failed: {e}. Retrying in 5 seconds...")
        time.sleep(5)


# --- Stream Processing ---
print(f"Connecting to Wikimedia stream: {WIKIMEDIA_STREAM_URL}")
print("Waiting for page-move events...")

while True:
    try:
        with requests.get(WIKIMEDIA_STREAM_URL, stream=True, timeout=90, headers=HEADERS) as response:
            if response.status_code == 200:
                print("✅ Stream connection successful. Waiting for events...")
                line_buffer = b''
                for chunk in response.iter_content(chunk_size=1):
                    if chunk:
                        line_buffer += chunk
                        if line_buffer.endswith(b'\n\n'):
                            event_str = line_buffer.decode('utf-8')
                            for line in event_str.splitlines():
                                if line.startswith('data: '):
                                    try:
                                        event_data = json.loads(line[6:])
                                        wiki_key = event_data.get('database', 'unknown_db')
                                        producer.produce(KAFKA_TOPIC, key=wiki_key.encode('utf-8'), value=json.dumps(event_data).encode('utf-8'))
                                        print(str(datetime.now()) + f" - Sent page-move event from '{wiki_key}'")
                                    except Exception as e:
                                        print(f"Error processing event data: {e}")
                            producer.flush(timeout=5)
                            line_buffer = b''
            else:
                print(f"Error connecting to stream: Status {response.status_code} - {response.reason}")

    except requests.exceptions.RequestException as e:
        print(f"Connection lost: {e}")
    
    print("Retrying connection in 10 seconds...")
    time.sleep(10)
