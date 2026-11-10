"""Metadatos de infraestructura local del servidor; sin endpoints sync."""
from sqlalchemy import (Table,Column,BigInteger,Integer,String,Text,DateTime,LargeBinary,
    ForeignKey,ForeignKeyConstraint,UniqueConstraint,CheckConstraint,text)
from sqlalchemy.dialects.postgresql import UUID,JSONB
from app.db.base import Base

identities=Table('plant_identities',Base.metadata,
    Column('id',UUID,primary_key=True),Column('owner_id',UUID,ForeignKey('users.id',ondelete='RESTRICT'),nullable=False),
    Column('state',String(30),nullable=False),Column('revision',BigInteger,nullable=False),
    UniqueConstraint('owner_id','id'),CheckConstraint("state IN ('full','historical_only')",name='state'),CheckConstraint('revision>0',name='positive_revision'))
owner_state=Table('sync_owner_state',Base.metadata,
    Column('owner_id',UUID,ForeignKey('users.id',ondelete='RESTRICT'),primary_key=True),
    Column('epoch',UUID,nullable=False,server_default=text('gen_random_uuid()')),
    Column('last_sequence',BigInteger,nullable=False,server_default=text('0')),CheckConstraint('last_sequence>=0',name='sequence'))
operations=Table('sync_operations',Base.metadata,
    Column('owner_id',UUID,ForeignKey('sync_owner_state.owner_id',ondelete='RESTRICT'),primary_key=True),
    Column('operation_id',UUID,primary_key=True),Column('format',Text,nullable=False),
    Column('canonical_request',Text,nullable=False),Column('fingerprint',LargeBinary,nullable=False),
    Column('action',Text,nullable=False),Column('entity_id',UUID),Column('terminal_status',Text,nullable=False),
    Column('receipt',JSONB,nullable=False),Column('response_status',Integer,nullable=False),Column('response_body',LargeBinary,nullable=False),
    Column('content_type',Text),Column('location',Text),Column('etag',Text),Column('epoch',UUID),Column('committed_sequence',BigInteger),
    Column('created_at',DateTime(timezone=True),nullable=False,server_default=text('clock_timestamp()')),
    CheckConstraint('octet_length(fingerprint)=32',name='fingerprint'),
    CheckConstraint("terminal_status IN ('applied','conflict','rejected')",name='terminal'),
    CheckConstraint('(epoch IS NULL)=(committed_sequence IS NULL)',name='sequence_pair'),
    ForeignKeyConstraint(['owner_id','epoch','committed_sequence'],['sync_change_groups.owner_id','sync_change_groups.epoch','sync_change_groups.sequence'],deferrable=True,initially='DEFERRED',use_alter=True,name='fk_operation_group'))
groups=Table('sync_change_groups',Base.metadata,
    Column('owner_id',UUID,ForeignKey('sync_owner_state.owner_id',ondelete='RESTRICT'),primary_key=True),
    Column('epoch',UUID,primary_key=True),Column('sequence',BigInteger,primary_key=True),
    Column('change_id',UUID,nullable=False),Column('operation_id',UUID,nullable=False),Column('images',JSONB,nullable=False),
    UniqueConstraint('owner_id','operation_id',name='uq_group_operation'),UniqueConstraint('owner_id','change_id',name='uq_group_change'),
    CheckConstraint('sequence>0',name='positive_sequence'),
    CheckConstraint("jsonb_typeof(images)='array' AND jsonb_array_length(images) BETWEEN 1 AND 4",name='images'),
    CheckConstraint("octet_length(convert_to(jsonb_build_object('sequence',sequence::text,'change_id',change_id,'operation_id',operation_id,'entities',images)::text,'UTF8'))<=65536",name='images_size'),
    ForeignKeyConstraint(['owner_id','operation_id'],['sync_operations.owner_id','sync_operations.operation_id'],deferrable=True,initially='DEFERRED'))
