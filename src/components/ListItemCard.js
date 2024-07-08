// src/components/ListItemCard.js
import React from 'react';
import { Card } from 'react-bootstrap';

function ListItemCard({ page }) {
  return (
    <a href={`/p/${page.dir}/index.html`} className="card-link">
      <Card style={{ width: '18rem' }} className="mb-3">
        <Card.Img variant="top" src={page.image} alt={page.title} />
        <Card.Body>
          <Card.Title>{page.title}</Card.Title>
        </Card.Body>
      </Card>
    </a>
  );
}

export default ListItemCard;
