import express from 'express';
import * as jose from 'jose';
import { Server } from 'http';

export class MockAuthServer {
  private app = express();
  private server: Server | null = null;
  private keyPair!: jose.GenerateKeyPairResult;
  public port: number;
  public hostIp: string; // Your machine's local network IP

  constructor(port: number, hostIp: string) {
    this.port = port;
    this.hostIp = hostIp; // e.g., '192.168.1.123'
  }

  // The URL the canister will use to reach this server
  public get issuerUrl(): string {
    return `http://${this.hostIp}:${this.port}`;
  }

  public get jwksUri(): string {
    return `${this.issuerUrl}/jwks.json`;
  }

  public get privateKey(): jose.CryptoKey {
    return this.keyPair.privateKey;
  }

  public async start(): Promise<void> {
    // Generate a single key pair for the server's lifetime
    this.keyPair = await jose.generateKeyPair('ES256', { extractable: true });

    // Endpoint for the OIDC discovery document
    this.app.get('/.well-known/oauth-authorization-server', (req, res) => {
      res.json({
        issuer: this.issuerUrl,
        jwks_uri: this.jwksUri,
      });
    });

    // Endpoint for the JSON Web Key Set
    this.app.get('/jwks.json', async (req, res) => {
      const jwk = await jose.exportJWK(this.keyPair.publicKey);
      res.json({
        keys: [{ ...jwk, kid: 'test-key-2025', use: 'sig' }],
      });
    });

    return new Promise((resolve) => {
      this.server = this.app.listen(this.port, '0.0.0.0', () => {
        console.log(`Mock Auth Server listening at ${this.issuerUrl}`);
        resolve();
      });
    });
  }

  public stop(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.server) {
        this.server.close((err) => {
          if (err) return reject(err);
          console.log('Mock Auth Server stopped.');
          resolve();
        });
      } else {
        resolve();
      }
    });
  }
}