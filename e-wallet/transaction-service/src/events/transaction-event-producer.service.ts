import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Kafka, Producer, CompressionTypes } from 'kafkajs';

@Injectable()
export class TransactionEventProducerService implements OnModuleInit {
  private readonly logger = new Logger(TransactionEventProducerService.name);
  private producer: Producer;
  private readonly topic: string;

  constructor(private readonly cfg: ConfigService) {
    const brokers = (cfg.get('KAFKA_BROKERS') || 'localhost:9092')
      .split(',')
      .map((b: string) => b.trim());
    const clientId = cfg.get('KAFKA_CLIENT_ID') || 'transaction-service';
    this.topic = cfg.get('KAFKA_TOPIC') || 'transaction-events';

    const kafka = new Kafka({ clientId, brokers });
    this.producer = kafka.producer({
      allowAutoTopicCreation: true,
      idempotent: true,
    });
  }

  async onModuleInit() {
    try {
      await this.producer.connect();
      this.logger.log(`Kafka producer connected to topic "${this.topic}"`);
    } catch (error: any) {
      this.logger.error(
        `Failed to connect Kafka producer: ${error?.message ?? error}`,
      );
    }
  }

  async publish(event: Record<string, any>): Promise<void> {
    const key = event.transactionId || event.eventType || 'unknown';
    try {
      await this.producer.send({
        topic: this.topic,
        compression: CompressionTypes.GZIP,
        messages: [
          {
            key: String(key),
            value: JSON.stringify(event),
            headers: {
              eventType: event.eventType || 'transaction.updated',
            },
          },
        ],
      });
    } catch (error: any) {
      this.logger.error(
        `Kafka publish failed: ${error?.message ?? error}`,
      );
      throw error;
    }
  }
}
